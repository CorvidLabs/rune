# frozen_string_literal: true

require 'pty'
require 'timeout'
require_relative 'parsers/text_sanitizer'

module Rune
  class PTYRunner
    PROMPT_REGEX = %r{(?::\s*|\?\s*|\[[yY]/[nN]\]\s*|:\s*\Z|\$\s*\Z|#\s*\Z)}

    attr_reader :command, :timeout_seconds

    def initialize(command, timeout_seconds: 30)
      @command = command.is_a?(Array) ? command.join(' ') : command.to_s
      @timeout_seconds = timeout_seconds
    end

    def run
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw_output, exit_code, prompt_detected = execute_pty

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
      clean_output = Parsers::TextSanitizer.strip_ansi(raw_output)

      Result.success({
                       command: command,
                       exit_code: exit_code || 0,
                       clean_output: clean_output,
                       raw_output: raw_output,
                       prompt_detected: prompt_detected,
                       duration_ms: duration_ms
                     })
    rescue StandardError => e
      Result.failure("Failed to execute command '#{command}': #{e.message}")
    end

    private

    def execute_pty
      raw_output = +''
      exit_code = nil
      prompt_detected = false

      Timeout.timeout(timeout_seconds) do
        PTY.spawn(command) do |r, _w, pid|
          prompt_detected = read_pty_stream(r, raw_output)
          _, status = Process.wait2(pid)
          exit_code = status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
        end
      end

      [raw_output, exit_code, prompt_detected]
    rescue Timeout::Error
      [raw_output + "\n[rune] Execution timed out after #{timeout_seconds} seconds", 124, false]
    end

    def read_pty_stream(reader, output_buffer)
      prompt_found = false
      reader.each_line do |line|
        output_buffer << line
        prompt_found = true if line.match?(PROMPT_REGEX)
      end
      prompt_found
    rescue Errno::EIO
      prompt_found
    end
  end
end
