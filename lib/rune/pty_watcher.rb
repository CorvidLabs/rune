# frozen_string_literal: true

require 'json'
require 'shellwords'
require_relative 'signal_handler'

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
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      PTY.spawn(env, @command) do |r, w, pid|
        SignalHandler.with_traps(pid) do |forward_signal|
          log_event('start', command: @command, pid: pid)
          exit_code = with_raw_input { pump_session(r, w, pid, forward_signal) }
        end
      end

      log_event('exit', exit_code: exit_code)
      Result.success({ command: @command, exit_code: exit_code || 0 }, exit_code: exit_code || 0)
    end

    def with_raw_input(&block)
      return block.call unless @input.respond_to?(:raw)

      @input.raw(&block)
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
