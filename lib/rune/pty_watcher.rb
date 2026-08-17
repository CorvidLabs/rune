# frozen_string_literal: true

require 'json'
require 'shellwords'
require 'timeout'
# IO#wait_readable is provided by this stdlib extension, not by 'pty' or
# 'io/console' — without it, pump_output's #wait_readable call crashes with
# a raw NoMethodError on Ruby versions where it isn't already autoloaded as
# part of core IO (same issue fixed in pty_runner.rb).
require 'io/wait'
require_relative 'signal_handler'
require_relative 'utf8_stream_decoder'

# Needed so the *parent* process's own $stdin/$stdout gain #raw/#getch —
# without this, with_raw_input's real raw-mode call was never reachable at
# all for the actual CLI (only a *child* command that happens to require
# 'io/console' itself would ever see it), silently leaving the terminal in
# normal cooked+echo mode. Cooked mode both echoes keystrokes locally *and*
# line-buffers them at the kernel level, so anything without a trailing
# newline (arrow keys, single-char menu input) never even reached the
# forwarding thread — a real bug found via live terminal testing, not a
# hypothetical. Rescued the same way pty_runner.rb rescues 'pty': io/console
# is expected almost everywhere but isn't guaranteed on every platform.
begin
  require 'io/console'
rescue LoadError
  nil
end

module Rune
  # Live, bidirectional interactive passthrough for a command in a PTY: the
  # human's real keystrokes are forwarded to the child as they're typed, the
  # child's output streams to the screen as it arrives (unlike PTYRunner,
  # which buffers everything and only returns it once the command finishes),
  # and every chunk is simultaneously logged as an NDJSON event so an agent
  # can tail the session live. A new, separate class rather than a PTYRunner
  # mode: PTYRunner's "run, capture, return once" contract is frozen for
  # 0.2.0, and the execution model here (raw terminal mode, a background
  # input-forwarding thread) is different enough to not belong bolted on.
  # rubocop:disable Metrics/ClassLength -- PTY lifecycle, terminal synchronization, and stream
  # cleanup are deliberately kept together so every spawned-child exit path remains auditable.
  class PTYWatcher
    # rubocop:disable Metrics/ParameterLists -- five independent constructor knobs (log/input/
    # output injection plus the two opt-in timeout bounds) read more clearly as named kwargs than
    # folded into one options hash; matches pty_runner.rb's tolerance for the same trade-off.
    def initialize(command, log: $stderr, input: $stdin, output: $stdout, timeout_seconds: nil,
                   idle_timeout_seconds: nil)
      # rubocop:enable Metrics/ParameterLists
      @command = command.is_a?(Array) ? Shellwords.join(command) : command.to_s
      @argv_form = command.is_a?(Array)
      @spawn_arguments = @argv_form ? command.map(&:to_s) : [@command]
      @log = log
      @input = input
      @output = output
      @timeout_seconds = timeout_seconds
      @idle_timeout_seconds = idle_timeout_seconds
      @timed_out_kind = nil
      @window_size = nil
    end

    def watch
      return Result.failure('rune watch requires a real terminal (stdin is not a TTY).') unless @input.tty?
      return Result.failure('PTY unavailable: pty stdlib failed to load.') unless PTYRunner.pty_available?

      run_session
    rescue StandardError => e
      Result.failure("Failed to watch command '#{@command}': #{e.message}")
    end

    private

    def run_session
      exit_code = nil
      spawned_pid = nil
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      PTY.spawn(env, *ExecArgv.for_spawn(@spawn_arguments, argv: @argv_form)) do |r, w, pid|
        spawned_pid = pid
        SignalHandler.with_traps(pid) do |forward_signal|
          synchronize_window_size(w)
          log_event('start', command: @command, pid: pid)
          exit_code = run_with_timeout(pid) { with_raw_input { pump_session(r, w, pid, forward_signal) } }
        end
      end

      build_result(exit_code, started_at)
    # A repeated INT/TERM: the signal itself was already forwarded to the child
    # on the way out, and unwinding through `with_raw_input` has already put the
    # human's terminal back into cooked mode, so all that is left is to make sure
    # the child is actually gone (bounded grace, then SIGKILL) and to report the
    # session at the conventional 128 + signo status instead of hanging.
    rescue SignalHandler::Aborted => e
      interrupted_result(e, spawned_pid, started_at)
    # Same conventional exit codes PTYRunner already returns for a missing
    # (127) or non-executable (126) wrapped command, instead of collapsing
    # both into a generic rune-level failure.
    rescue Errno::ENOENT
      build_result(127, started_at)
    rescue Errno::EACCES
      build_result(126, started_at)
    end

    # Bounds total session wall-clock time with --timeout, same mechanism
    # PTYRunner already uses (Timeout.timeout only interrupts rune's own
    # control flow, so the orphaned child still needs an explicit kill+reap).
    # A no-op wrapper when --timeout wasn't given, so the untimed path is
    # identical to before this option existed. --idle-timeout is unrelated:
    # it's checked cooperatively inside pump_output's own poll loop, since
    # "no activity for N seconds" can't be expressed as a single deadline.
    def run_with_timeout(pid, &block)
      return block.call unless @timeout_seconds

      Timeout.timeout(@timeout_seconds, &block)
    rescue Timeout::Error
      terminate_child(pid)
      @timed_out_kind = :timeout
      log_event('timeout', timeout_seconds: @timeout_seconds)
      124
    end

    # A repeated INT/TERM ended the session. The signal itself was already
    # forwarded to the child on the way out, and unwinding through
    # `with_raw_input` has already put the human's terminal back into cooked
    # mode, so all that is left is making sure the child is gone and reporting
    # the conventional 128 + signo status instead of hanging. The reap is a
    # bounded net: pump_output already reaps while its pty reader is open,
    # which is the only place a wedged child can be drained free.
    def interrupted_result(error, pid, started_at)
      SignalHandler.reap(pid)
      log_event('interrupted', signal: error.signal_name)
      build_result(error.exit_code, started_at)
    end

    def build_result(exit_code, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      log_event('exit', exit_code: exit_code)
      data = { command: @command, exit_code: exit_code || 0, duration_ms: duration_ms }
      if @timed_out_kind
        data[:timed_out] = true
        data[:timeout_kind] = @timed_out_kind.to_s
      end
      Result.success(data, exit_code: exit_code || 0)
    end

    # Requiring 'io/console' adds #raw to every IO, tty-backed or not, so
    # respond_to?(:raw) can no longer distinguish a real terminal from a
    # plain pipe (as used by the test suite's fake input objects) — calling
    # it and rescuing the OS's own "not a tty" error is the only reliable
    # check. NoMethodError is a second fallback for the (now rare) case
    # io/console failed to load at all.
    #
    # The `entered` flag is load-bearing, not decorative: without it, an
    # unrelated NoMethodError raised from deep inside the block (e.g. an
    # injected output object missing #flush) would also be caught here and
    # silently re-run the ENTIRE already-spawned PTY session a second time
    # via the block.call fallback below — re-entering signal traps,
    # re-spawning the input-forwarding thread, all of it. Only fall back
    # when the failure happened before the block ever started running.
    def with_raw_input(&block)
      entered = false
      @input.raw do
        entered = true
        block.call
      end
    rescue Errno::ENOTTY, NoMethodError
      raise if entered

      block.call
    end

    def pump_session(reader, writer, pid, forward_signal)
      input_thread = forward_input(writer)
      pump_output(reader, writer, pid, forward_signal)
    ensure
      input_thread&.kill
    end

    # Never blocks process exit on a thread stuck in a blocking read: the
    # human's terminal, once returned to cooked mode, needs no more forwarding.
    # Touches @last_activity_at (also written from pump_output's thread) on
    # every chunk read from the human, not just ones actually forwarded, so
    # --idle-timeout counts genuine typing as activity even the instant before
    # the child exits and the writer stops accepting more.
    def forward_input(writer)
      thread = Thread.new do
        loop do
          chunk = @input.readpartial(4096)
          @last_activity_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          writer.write(chunk)
        rescue IOError, Errno::EIO, Errno::EBADF
          break
        end
      end
      thread.report_on_exception = false
      thread
    end

    def pump_output(reader, writer, pid, forward_signal)
      decoder = UTF8StreamDecoder.new
      @last_activity_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        forward_signal.call
        synchronize_window_size(writer)
        return idle_timeout_result(pid) if idle_timed_out?
        next unless reader.wait_readable(0.2)

        emit_output(decoder.decode(reader.readpartial(4096)))
      end
    rescue Errno::EIO, EOFError, PTY::ChildExited
      emit_output(decoder.finish)
      wait_for_exit_code(pid)
    rescue SignalHandler::Aborted
      # Reaped here, with the pty reader still open, for the reason spelled out
      # in SignalHandler.reap: a SIGKILLed pty child holding unread output
      # wedges unreapably on macOS, and only draining the master clears it.
      # Draining also keeps the child's final bytes on screen and in the log.
      SignalHandler.reap(pid) { drain_available(reader, decoder) }
      raise
    rescue Errno::EPIPE
      terminate_child(pid)
      raise
    end

    # One bounded, best-effort read used while tearing a session down.
    def drain_available(reader, decoder)
      return unless reader.wait_readable(0.01)

      emit_output(decoder.decode(reader.readpartial(4096)))
    rescue Errno::EIO, Errno::EPIPE, PTY::ChildExited, IOError # IOError covers EOFError
      nil
    end

    def emit_output(chunk)
      return if chunk.empty?

      @last_activity_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @output.write(chunk)
      @output.flush
      log_event('output', bytes: chunk.bytesize, text: chunk)
    end

    # --idle-timeout bounds "no output and no input", not total wall-clock —
    # checked cooperatively here on the same ~0.2s cadence pump_output already
    # polls at, rather than as a single Timeout.timeout deadline (which can
    # only express a total duration, not a resettable idle window).
    def idle_timed_out?
      return false unless @idle_timeout_seconds

      Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_activity_at >= @idle_timeout_seconds
    end

    def idle_timeout_result(pid)
      terminate_child(pid)
      @timed_out_kind = :idle_timeout
      log_event('idle_timeout', idle_timeout_seconds: @idle_timeout_seconds)
      124
    end

    def synchronize_window_size(writer)
      return unless @input.respond_to?(:winsize) && writer.respond_to?(:winsize=)

      size = @input.winsize
      return if size == @window_size
      return unless valid_window_size?(size)

      writer.winsize = size
      @window_size = size
    rescue IOError, SystemCallError
      nil
    end

    def valid_window_size?(size)
      size.is_a?(Array) && size.size == 2 && size.all? { |value| value.is_a?(Integer) && value.positive? }
    end

    # grace_seconds: 0 keeps the existing straight-to-SIGKILL semantics for the
    # timeout/idle-timeout/EPIPE paths; the wait after it is bounded rather
    # than a plain `Process.wait` so a wedged pty child (see SignalHandler.reap)
    # cannot turn a bound into an unbounded hang.
    def terminate_child(pid)
      SignalHandler.reap(pid, grace_seconds: 0)
    end

    def wait_for_exit_code(pid)
      _, status = Process.wait2(pid)
      status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
    rescue Errno::ECHILD
      0
    end

    def log_event(event, **fields)
      return unless @log

      @log.puts JSON.generate({ event: event, ts: Time.now.to_f }.merge(fields))
      @log.flush
    end
  end
  # rubocop:enable Metrics/ClassLength
end
