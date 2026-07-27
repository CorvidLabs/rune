# frozen_string_literal: true

require_relative 'text_sanitizer'

module Rune
  module Parsers
    class TableParser
      class << self
        # format: :auto (default, detects pipe vs. space by scanning the header line for `|`),
        # :pipe (force markdown-style `| a | b |` parsing), or :space (force whitespace-column
        # parsing). Force :space or :pipe when the heuristic misdetects a table — e.g. free text
        # containing a literal `|` character, or space-delimited data whose columns don't align
        # on a consistent 2+-space gap.
        def parse(text, format: :auto)
          # Validated unconditionally, before the short-input early return
          # below — otherwise `parse('', format: :bogus)` silently returned
          # `[]` instead of raising, making acceptance of an unsupported
          # format depend on how many rows happened to be in the input.
          validate_format!(format)
          raw_lines = clean_lines(text)
          return [] if raw_lines.size < 2

          lines = raw_lines.map { |l| TextSanitizer.strip_ansi(l) }

          case resolve_format(format, lines)
          when :pipe then parse_pipe_table(lines)
          when :space then parse_space_table(lines)
          end
        end

        private

        def validate_format!(format)
          return if %i[auto pipe space].include?(format)

          raise ArgumentError, "Unknown TableParser format: #{format.inspect} (expected :auto, :pipe, or :space)"
        end

        def resolve_format(format, lines)
          return lines.first.include?('|') ? :pipe : :space if format == :auto

          format
        end

        def clean_lines(text)
          return [] if text.nil?

          text.strip.split("\n").reject do |l|
            stripped = TextSanitizer.strip_ansi(l).strip
            stripped.empty? || stripped.match?(/\A[|\s\-+=:]+\z/)
          end
        end

        def parse_pipe_table(lines)
          headers = lines.first.split('|').map(&:strip).reject(&:empty?).map { |h| normalize_header(h) }
          lines[1..].map do |line|
            values = line.split('|').map(&:strip).reject(&:empty?)
            build_row(headers, values)
          end
        end

        def parse_space_table(lines)
          header_line = lines.first
          headers, spans = find_headers_and_spans(header_line)

          lines[1..].map do |line|
            values = extract_values(line, headers.size, spans)
            build_row(headers, values)
          end
        end

        def find_headers_and_spans(header_line)
          raw_headers = header_line.split(/\s{2,}/).map(&:strip).reject(&:empty?)
          return multi_space_spans(header_line, raw_headers) if raw_headers.size > 1

          single_space_spans(header_line)
        end

        def multi_space_spans(header_line, raw_headers)
          spans = []
          search_start = 0
          raw_headers.each do |h|
            idx = header_line.index(h, search_start) || search_start
            spans << { name: h, start: idx }
            search_start = idx + h.length
          end
          set_span_ends(spans, header_line.length)
          [raw_headers.map { |h| normalize_header(h) }, spans]
        end

        def single_space_spans(header_line)
          spans = []
          header_line.scan(/\S+/) do |match|
            spans << { name: match, start: Regexp.last_match.begin(0) }
          end
          set_span_ends(spans, header_line.length)
          [spans.map { |s| normalize_header(s[:name]) }, spans]
        end

        def set_span_ends(spans, total_length)
          spans.each_with_index do |span, idx|
            span[:end] = idx < spans.size - 1 ? spans[idx + 1][:start] - 1 : total_length
          end
        end

        def extract_values(line, num_headers, spans)
          space_split = line.strip.split(/\s{2,}/)
          return space_split if space_split.size == num_headers

          if space_split.size > num_headers
            return space_split[0...(num_headers - 1)] + [space_split[(num_headers - 1)..].join('  ')]
          end

          extract_by_spans(line, num_headers, spans)
        end

        def extract_by_spans(line, num_headers, spans)
          values = spans.each_with_index.map do |span, idx|
            val = idx == spans.size - 1 ? (line[span[:start]..] || '') : (line[span[:start]..span[:end]] || '')
            val.strip
          end
          values << '' while values.size < num_headers
          values
        end

        def normalize_header(header)
          header.downcase.gsub(/\s+/, '_').to_sym
        end

        def build_row(headers, values)
          headers.each_with_index.with_object({}) do |(header, idx), hash|
            hash[header] = values[idx] || ''
          end
        end
      end
    end
  end
end
