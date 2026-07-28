# frozen_string_literal: true

# The pty stdlib is unavailable on some platforms (e.g. Windows) and in some
# sandboxed/containerized environments. Rescuing here keeps the rest of rune
# (version, help, anything not touching PTYRunner) usable even when it's
# missing, instead of crashing the whole binary at boot with a bare LoadError.
begin
  require 'pty'
  PTY_LOAD_ERROR = nil
rescue LoadError => e
  PTY_LOAD_ERROR = e
end

require 'timeout'
require 'shellwords'
# IO#wait_readable/#wait_writable are provided by this stdlib extension, not
# by 'pty' itself. On Ruby versions where it isn't already autoloaded as part
# of core IO, every #run would otherwise crash with a raw NoMethodError the
# moment read_pty_stream calls #wait_readable — found via a real triage
# against a Ruby 3.1 install, inside this gem's own declared >= 3.0 support
# range.
require 'io/wait'
require_relative 'parsers/text_sanitizer'
require_relative 'parsers/prompt_detector'
require_relative 'signal_handler'
require_relative 'utf8_stream_decoder'

module Rune
  # rubocop:disable Metrics/ClassLength -- grew past the limit from the timeout-kill and io/wait
  # fixes; the spawn/read/signal-forwarding logic here is tightly coupled and splitting it across
  # files for a line-count metric alone would hurt readability more than it helps.
  class PTYRunner
    attr_reader :command, :input, :script, :timeout_seconds, :on_output

    # Raised when the OS itself refuses to allocate a pty (device exhaustion,
    # a sandbox/container denying it), as opposed to Errno::ENOENT/EACCES from
    # exec'ing the *target* command, which are a property of the wrapped
    # command and already handled as ordinary exit codes in execute_pty.
    PTY_ALLOCATION_ERRORS = [Errno::ENXIO, Errno::EMFILE, Errno::ENFILE, Errno::EPERM].freeze

    def self.pty_available? = PTY_LOAD_ERROR.nil?

    def initialize(command, input: nil, script: nil, timeout_seconds: 30, &on_output)
      @command = command.is_a?(Array) ? Shellwords.join(command) : command.to_s
      @input = input
      @script = script
      @timeout_seconds = timeout_seconds
      @on_output = on_output
    end

    def run
      return pty_unavailable_result unless self.class.pty_available?

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw_output, exit_code, prompt_detected = execute_pty

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
      clean_output = Parsers::TextSanitizer.strip_ansi(raw_output)

      Result.success({ command: command, exit_code: exit_code || 0, clean_output: clean_output,
                       raw_output: raw_output, prompt_detected: prompt_detected, duration_ms: duration_ms },
                     exit_code: exit_code || 0)
    rescue *PTY_ALLOCATION_ERRORS => e
      Result.failure("PTY allocation failed at runtime: #{e.class} - #{e.message}. Platform/sandbox may restrict it.")
    rescue StandardError => e
      Result.failure("Failed to execute command '#{command}': #{e.message}")
    end

    def detect_prompt?(line) = Parsers::PromptDetector.detect?(line)

    private

    def pty_unavailable_result
      Result.failure("PTY unavailable: pty stdlib failed to load (#{PTY_LOAD_ERROR&.message}).")
    end

    def execute_pty
      raw_output = +''
      exit_code = nil
      prompt_detected = false
      spawned_pid = nil

      Timeout.timeout(timeout_seconds) do
        prompt_detected, exit_code = spawn_and_stream(raw_output) { |pid| spawned_pid = pid }
      end

      [raw_output, exit_code, prompt_detected]
    rescue Errno::ENOENT then ["Command not found: #{command}", 127, false]
    rescue Errno::EACCES then ["Permission denied: #{command}", 126, false]
    rescue Timeout::Error
      # Timeout.timeout only interrupts Ruby's control flow — the spawned OS
      # process keeps running as an orphan unless killed explicitly here.
      kill_orphaned_child(spawned_pid)
      ["#{raw_output}\n[rune] Execution timed out after #{timeout_seconds} seconds", 124, false]
    rescue PTY::ChildExited then [raw_output, 0, prompt_detected]
    end

    def spawn_and_stream(raw_output, &on_pid)
      exit_code = nil
      prompt_detected = false
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      PTY.spawn(env, command) do |r, w, pid|
        on_pid&.call(pid)
        SignalHandler.with_traps(pid) do |forward_signal|
          write_input(w, input) if input
          prompt_detected = read_pty_stream(r, w, raw_output, forward_signal)
          exit_code = wait_for_process(pid)
        end
      end
      [prompt_detected, exit_code]
    end

    # SIGKILL, not SIGTERM: the process already overran its allotted time, so
    # there's no value giving it another chance to ignore a softer signal.
    def kill_orphaned_child(pid)
      return unless pid

      Process.kill('KILL', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def wait_for_process(pid)
      _, status = Process.wait2(pid)
      status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
    rescue Errno::ECHILD
      0
    end

    def write_input(writer, data)
      return if data.nil? || data.empty?

      writable = writer.wait_writable(2.0) rescue nil # rubocop:disable Style/RescueModifier
      return unless writable

      writer.write_nonblock(data)
      writer.flush
    rescue StandardError
      nil
    end

    # Polls with a short readable-wait rather than blocking indefinitely on
    # readpartial, so a caught signal gets forwarded promptly instead of
    # waiting for the next chunk of child output (which may never come).
    def read_pty_stream(reader, writer, output_buffer, forward_signal)
      prompt_found = false
      script_step_index = 0
      decoder = UTF8StreamDecoder.new
      loop do
        forward_signal.call
        next unless reader.wait_readable(0.2)

        chunk = decoder.decode(reader.readpartial(4096))
        prompt_found, script_step_index = consume_output_chunk(
          chunk, output_buffer, writer, prompt_found, script_step_index
        )
      end
    rescue Errno::EIO, EOFError, PTY::ChildExited, Errno::EPIPE
      prompt_found, = consume_output_chunk(
        decoder.finish, output_buffer, writer, prompt_found, script_step_index
      )
      prompt_found
    end

    def consume_output_chunk(chunk, output_buffer, writer, prompt_found, script_step_index)
      return [prompt_found, script_step_index] if chunk.empty?

      output_buffer << chunk
      on_output&.call(chunk)
      prompt_found ||= chunk.split("\n").any? { |line| detect_prompt?(line) }
      script_step_index = process_script_steps(script_step_index, output_buffer, writer) if script
      [prompt_found, script_step_index]
    end

    def process_script_steps(current_index, buffer, writer)
      return current_index if script.nil?

      while current_index < script.steps.size
        step = script.steps[current_index]
        case step.type
        when :wait_for then break unless buffer.match?(step.payload)
        when :send_keys then write_input(writer, step.payload)
        when :pause then sleep(step.payload)
        end
        current_index += 1
      end
      current_index
    end
  end
  # rubocop:enable Metrics/ClassLength
end
