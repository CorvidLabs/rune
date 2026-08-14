# frozen_string_literal: true

require_relative '../pty_runner'

module Rune
  module Commands
    class RunCommand < Command
      name 'run'
      summary 'Execute any CLI command in a PTY and return structured output'
      usage 'rune run [--timeout=SECONDS] [--max-output=BYTES] [--tail=N] [--] <command...>'
      flag '--timeout=SECONDS', 'Kill the wrapped command after N seconds (default 30). Before `--` only.'
      flag '--max-output=BYTES',
           'Bound clean_output/raw_output to BYTES each, keeping head+tail. ' \
           'Mutually exclusive with --tail. Before `--` only.'
      flag '--tail=N',
           'Keep only the last N lines of clean_output/raw_output. ' \
           'Mutually exclusive with --max-output. Before `--` only.'

      def call(args, _options)
        flags, remaining, flag_error = extract_flags(args)
        return Result.failure(flag_error) if flag_error

        # Only drop rune's own leading separator (guaranteed to be at index 0
        # if extract_flags found one) — not every `--` in the array. Many
        # wrapped commands (cargo, npm, git) use `--` themselves to separate
        # their own flags from pass-through args, e.g.
        # `rune run -- cargo clippy --tests -- -D warnings`; blindly
        # rejecting every `--` corrupted that inner separator.
        clean_args = remaining.first == '--' ? remaining[1..] : remaining
        if clean_args.empty?
          return Result.failure(
            'No command specified. Usage: rune run [--timeout=SECONDS] [--max-output=BYTES] [--tail=N] <command...>'
          )
        end

        PTYRunner.new(clean_args, **flags).run
      end

      def human_render(data, io)
        icon = data[:exit_code].zero? ? "\e[32m✓\e[0m" : "\e[31m✗\e[0m"
        header = "#{icon} \e[1m#{data[:command]}\e[0m " \
                 "(\e[36m#{data[:duration_ms]}ms\e[0m, exit \e[1m#{data[:exit_code]}\e[0m)"

        io.puts header
        io.puts ''
        io.puts data[:clean_output]
      end

      # Recognized before a `--` separator only; anything after it is the
      # wrapped command's own argv and must be passed through untouched. Each
      # entry is [pattern, human label, value-kind description for the error
      # message]. --max-output and --tail are mutually exclusive: both map to
      # bounding the same captured output in incompatible units (bytes vs.
      # lines), so combining them has no single sensible meaning.
      FLAG_PATTERNS = {
        timeout_seconds: [/\A--timeout=(.*)\z/, '--timeout', 'number of seconds'],
        max_output_bytes: [/\A--max-output=(.*)\z/, '--max-output', 'number of bytes'],
        tail_lines: [/\A--tail=(.*)\z/, '--tail', 'number of lines']
      }.freeze

      private

      # Returns [PTYRunner_kwargs, remaining_args, error_message]. A malformed
      # value (non-numeric, zero, negative) is rejected explicitly here rather
      # than silently leaking the raw flag into the executed command string.
      def extract_flags(args)
        separator_index = args.index('--')
        head = separator_index ? args[0...separator_index] : args
        tail = separator_index ? args[separator_index..] : []

        raw_values = {}
        head = head.select do |arg|
          key, match = matching_flag(arg)
          raw_values[key] = match[1] if key
          key.nil?
        end

        flags, error = parse_flags(raw_values)
        [flags, head + tail, error]
      end

      def matching_flag(arg)
        FLAG_PATTERNS.each do |key, (pattern, _label, _unit)|
          match = arg.match(pattern)
          return [key, match] if match
        end
        [nil, nil]
      end

      def parse_flags(raw_values)
        flags = {}
        raw_values.each do |key, value|
          parsed, error = parse_positive_int(value, key)
          return [flags, error] if error

          flags[key] = parsed
        end

        return [flags, 'Cannot combine --max-output and --tail; use one or the other.'] if both_output_limits?(flags)

        [flags, nil]
      end

      def both_output_limits?(flags)
        flags.key?(:max_output_bytes) && flags.key?(:tail_lines)
      end

      def parse_positive_int(value, key)
        _pattern, label, unit = FLAG_PATTERNS.fetch(key)
        return [value.to_i, nil] if value.match?(/\A\d+\z/) && value.to_i.positive?

        [nil, "Invalid #{label} value: #{value.inspect}. Must be a positive integer #{unit}."]
      end
    end
  end
end
