# frozen_string_literal: true

require_relative '../pty_runner'

module Rune
  module Commands
    class RunCommand < Command
      name 'run'
      summary 'Execute any CLI command in a PTY and return structured output'
      usage 'rune run [--timeout=SECONDS] [--] <command...>'
      flag '--timeout=SECONDS', 'Kill the wrapped command after N seconds (default 30). Before `--` only.'

      def call(args, _options)
        timeout_seconds, remaining, timeout_error = extract_timeout(args)
        return Result.failure(timeout_error) if timeout_error

        # Only drop rune's own leading separator (guaranteed to be at index 0
        # if extract_timeout found one) — not every `--` in the array. Many
        # wrapped commands (cargo, npm, git) use `--` themselves to separate
        # their own flags from pass-through args, e.g.
        # `rune run -- cargo clippy --tests -- -D warnings`; blindly
        # rejecting every `--` corrupted that inner separator.
        clean_args = remaining.first == '--' ? remaining[1..] : remaining
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
      # Returns [timeout_seconds, remaining_args, error_message]; a malformed
      # value (non-numeric, zero, negative) is rejected explicitly here
      # rather than silently leaking into the executed command string.
      def extract_timeout(args)
        separator_index = args.index('--')
        head = separator_index ? args[0...separator_index] : args
        tail = separator_index ? args[separator_index..] : []

        timeout_seconds = nil
        error = nil
        head = head.reject do |arg|
          match = arg.match(/\A--timeout=(.*)\z/)
          next false unless match

          timeout_seconds, error = parse_timeout_value(match[1])
          true
        end

        [timeout_seconds, head + tail, error]
      end

      def parse_timeout_value(value)
        return [value.to_i, nil] if value.match?(/\A\d+\z/) && value.to_i.positive?

        [nil, "Invalid --timeout value: #{value.inspect}. Must be a positive integer number of seconds."]
      end
    end
  end
end
