# frozen_string_literal: true

module Rune
  module Parsers
    class TableParser
      class << self
        def parse(text)
          lines = clean_lines(text)
          return [] if lines.size < 2

          header_line = lines.first
          return parse_pipe_table(lines) if header_line.include?('|')

          parse_space_table(lines)
        end

        private

        def clean_lines(text)
          return [] if text.nil?

          text.strip.split("\n").reject do |l|
            stripped = l.strip
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
          header_matches = find_header_spans(header_line)
          headers = header_matches.map { |m| normalize_header(m[:name]) }

          lines[1..].map do |line|
            values = extract_column_values(line, header_matches)
            build_row(headers, values)
          end
        end

        def find_header_spans(line)
          spans = []
          line.scan(/\S+/) do |match|
            start_pos = Regexp.last_match.begin(0)
            spans << { name: match, start: start_pos }
          end

          spans.each_with_index do |span, idx|
            span[:end] = idx < spans.size - 1 ? spans[idx + 1][:start] - 1 : line.length
          end
          spans
        end

        def extract_column_values(line, spans)
          spans.map do |span|
            val = line[span[:start]..span[:end]]
            val ? val.strip : ''
          end
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
