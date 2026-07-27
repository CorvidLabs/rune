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
require_relative 'parsers/text_sanitizer'
require_relative 'parsers/prompt_detector'
require_relative 'signal_handler'

module Rune
  class PTYRunner
    attr_reader :command, :input, :script, :timeout_seconds, :on_output

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
    rescue StandardError => e
      Result.failure("Failed to execute command '#{command}': #{e.message}")
    end

    def detect_prompt?(line)
      Parsers::PromptDetector.detect?(line)
    end

    private

    def pty_unavailable_result
      Result.failure('PTY unavailable on this platform (pty stdlib failed to load: ' \
                     "#{PTY_LOAD_ERROR&.message}). rune run requires a Unix-like platform with pty support.")
    end

    def execute_pty
      raw_output = +''
      exit_code = nil
      prompt_detected = false

      Timeout.timeout(timeout_seconds) do
        prompt_detected, exit_code = spawn_and_stream(raw_output)
      end

      [raw_output, exit_code, prompt_detected]
    rescue Errno::ENOENT then ["Command not found: #{command}", 127, false]
    rescue Errno::EACCES then ["Permission denied: #{command}", 126, false]
    rescue Timeout::Error
      ["#{raw_output}\n[rune] Execution timed out after #{timeout_seconds} seconds", 124, false]
    rescue PTY::ChildExited then [raw_output, 0, prompt_detected]
    end

    def spawn_and_stream(raw_output)
      exit_code = nil
      prompt_detected = false
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      PTY.spawn(env, command) do |r, w, pid|
        SignalHandler.with_traps(pid) do |forward_signal|
          write_input(w, input) if input
          prompt_detected = read_pty_stream(r, w, raw_output, forward_signal)
          exit_code = wait_for_process(pid)
        end
      end
      [prompt_detected, exit_code]
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
      loop do
        forward_signal.call
        next unless reader.wait_readable(0.2)

        chunk = reader.readpartial(4096)
        output_buffer << chunk
        on_output&.call(chunk)
        prompt_found ||= chunk.split("\n").any? { |line| detect_prompt?(line) }
        script_step_index = process_script_steps(script_step_index, output_buffer, writer) if script
      end
    rescue Errno::EIO, EOFError, PTY::ChildExited, Errno::EPIPE
      prompt_found
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
end
