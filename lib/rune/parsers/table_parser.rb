# frozen_string_literal: true

module Rune
  module Parsers
    class TableParser
      class << self
        def parse(text)
          lines = clean_lines(text)
          return [] if lines.size < 2

          headers = extract_headers(lines.first)
          lines[1..].map { |line| build_row(headers, parse_line(line)) }
        end

        private

        def clean_lines(text)
          return [] if text.nil?

          text.strip.split("\n").reject do |l|
            stripped = l.strip
            stripped.empty? || stripped.match?(/\A[|\s\-+=:]+\z/)
          end
        end

        def extract_headers(header_line)
          parse_line(header_line).map { |h| h.downcase.gsub(/\s+/, '_').to_sym }
        end

        def build_row(headers, values)
          headers.each_with_index.with_object({}) do |(header, idx), hash|
            hash[header] = values[idx] || ''
          end
        end

        def parse_line(line)
          if line.include?('|')
            line.split('|').map(&:strip).reject(&:empty?)
          else
            line.split(/\s{2,}/).map(&:strip)
          end
        end
      end
    end
  end
end
