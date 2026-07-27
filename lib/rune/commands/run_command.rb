# frozen_string_literal: true

require_relative '../pty_runner'

module Rune
  module Commands
    class RunCommand < Command
      name 'run'
      summary 'Execute any CLI command in a PTY and return structured output'

      def call(args, _options)
        timeout_seconds, remaining = extract_timeout(args)
        clean_args = remaining.reject { |a| a == '--' }
        if clean_args.empty?
          return Result.failure('No command specified. Usage: rune run [--timeout=SECONDS] <command...>')
        end

        runner_options = timeout_seconds ? { timeout_seconds: timeout_seconds } : {}
        PTYRunner.new(clean_args, **runner_options).run
      end

      def human_render(data, io)
        icon = data[:exit_code].zero? ? "\e[32m✓\e[0m" : "\e[31m✗\e[0m"
        header = "#{icon} \e[1m#{data[:command]}\e[0m " \
                 "(\e[36m#{data[:duration_ms]}ms\e[0m, exit \e[1m#{data[:exit_code]}\e[0m)"

        io.puts header
        io.puts ''
        io.puts data[:clean_output]
      end

      private

      # Only flags before a `--` separator belong to rune; anything after it is
      # the wrapped command's own argv and must be passed through untouched.
      def extract_timeout(args)
        separator_index = args.index('--')
        head = separator_index ? args[0...separator_index] : args
        tail = separator_index ? args[separator_index..] : []

        timeout_seconds = nil
        head = head.reject do |arg|
          match = arg.match(/\A--timeout=(\d+)\z/)
          next false unless match

          timeout_seconds = match[1].to_i
          true
        end

        [timeout_seconds, head + tail]
      end
    end
  end
end
