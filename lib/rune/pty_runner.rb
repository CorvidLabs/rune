# frozen_string_literal: true

require 'pty'
require 'timeout'
require 'shellwords'
require_relative 'parsers/text_sanitizer'
require_relative 'parsers/prompt_detector'

module Rune
  class PTYRunner
    attr_reader :command, :input, :script, :timeout_seconds, :on_output

    def initialize(command, input: nil, script: nil, timeout_seconds: 30, &on_output)
      @command = command.is_a?(Array) ? Shellwords.join(command) : command.to_s
      @input = input
      @script = script
      @timeout_seconds = timeout_seconds
      @on_output = on_output
    end

    def run
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw_output, exit_code, prompt_detected = execute_pty

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
      clean_output = Parsers::TextSanitizer.strip_ansi(raw_output)

      Result.success({ command: command, exit_code: exit_code || 0, clean_output: clean_output,
                       raw_output: raw_output, prompt_detected: prompt_detected, duration_ms: duration_ms })
    rescue StandardError => e
      Result.failure("Failed to execute command '#{command}': #{e.message}")
    end

    def detect_prompt?(line)
      Parsers::PromptDetector.detect?(line)
    end

    private

    def execute_pty
      raw_output = +''
      exit_code = nil
      prompt_detected = false
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      Timeout.timeout(timeout_seconds) do
        PTY.spawn(env, command) do |r, w, pid|
          write_input(w, input) if input
          prompt_detected = read_pty_stream(r, w, raw_output)
          exit_code = wait_for_process(pid)
        end
      end

      [raw_output, exit_code, prompt_detected]
    rescue Errno::ENOENT
      ["Command not found: #{command}", 127, false]
    rescue Errno::EACCES
      ["Permission denied: #{command}", 126, false]
    rescue Timeout::Error
      ["#{raw_output}\n[rune] Execution timed out after #{timeout_seconds} seconds", 124, false]
    rescue PTY::ChildExited
      [raw_output, 0, prompt_detected]
    end

    def wait_for_process(pid)
      _, status = Process.wait2(pid)
      status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
    rescue Errno::ECHILD
      0
    end

    def write_input(writer, data)
      writer.write(data)
      writer.flush
    rescue StandardError
      nil
    end

    def read_pty_stream(reader, writer, output_buffer)
      prompt_found = false
      script_step_index = 0
      loop do
        chunk = reader.readpartial(4096)
        output_buffer << chunk
        on_output&.call(chunk)
        chunk.split("\n").each { |line| prompt_found = true if detect_prompt?(line) }
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
        when :wait_for
          break unless buffer.match?(step.payload)
        when :send_keys
          write_input(writer, step.payload)
        when :pause
          sleep(step.payload)
        end
        current_index += 1
      end
      current_index
    end
  end
end
