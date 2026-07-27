# frozen_string_literal: true

require 'json'
require 'shellwords'
# IO#wait_readable is provided by this stdlib extension, not by 'pty' or
# 'io/console' — without it, pump_output's #wait_readable call crashes with
# a raw NoMethodError on Ruby versions where it isn't already autoloaded as
# part of core IO (same issue fixed in pty_runner.rb).
require 'io/wait'
require_relative 'signal_handler'

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
  class PTYWatcher
    def initialize(command, log: $stderr, input: $stdin, output: $stdout)
      @command = command.is_a?(Array) ? Shellwords.join(command) : command.to_s
      @log = log
      @input = input
      @output = output
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
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      PTY.spawn(env, @command) do |r, w, pid|
        SignalHandler.with_traps(pid) do |forward_signal|
          log_event('start', command: @command, pid: pid)
          exit_code = with_raw_input { pump_session(r, w, pid, forward_signal) }
        end
      end

      build_result(exit_code, started_at)
    # Same conventional exit codes PTYRunner already returns for a missing
    # (127) or non-executable (126) wrapped command, instead of collapsing
    # both into a generic rune-level failure.
    rescue Errno::ENOENT
      build_result(127, started_at)
    rescue Errno::EACCES
      build_result(126, started_at)
    end

    def build_result(exit_code, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      log_event('exit', exit_code: exit_code)
      data = { command: @command, exit_code: exit_code || 0, duration_ms: duration_ms }
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
      pump_output(reader, pid, forward_signal)
    ensure
      input_thread&.kill
    end

    # Never blocks process exit on a thread stuck in a blocking read: the
    # human's terminal, once returned to cooked mode, needs no more forwarding.
    def forward_input(writer)
      thread = Thread.new do
        loop do
          chunk = @input.readpartial(4096)
          writer.write(chunk)
        rescue IOError, Errno::EIO, Errno::EBADF
          break
        end
      end
      thread.report_on_exception = false
      thread
    end

    def pump_output(reader, pid, forward_signal)
      loop do
        forward_signal.call
        next unless reader.wait_readable(0.2)

        chunk = reader.readpartial(4096).force_encoding(Encoding::UTF_8).scrub
        @output.write(chunk)
        @output.flush
        log_event('output', bytes: chunk.bytesize, text: chunk)
      end
    rescue Errno::EIO, EOFError, PTY::ChildExited
      wait_for_exit_code(pid)
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
end
