# frozen_string_literal: true

module Rune
  module Parsers
    class KeyValueParser
      class << self
        def parse(text)
          return {} if text.nil? || text.strip.empty?

          text.each_line.with_object({}) do |line, result|
            process_line(line.strip, result)
          end
        end

        private

        def process_line(line, result)
          return if line.empty? || line.start_with?('#', '//')

          parts = line.split(/[:=]/, 2)
          return unless parts.size == 2

          raw_key = parts[0].strip
          return if raw_key.empty? || raw_key.match?(/\s{2,}/)

          key = raw_key.downcase.gsub(/\s+/, '_').to_sym
          result[key] = coerce_value(parts[1].strip)
        end

        def coerce_value(value)
          return true if value == 'true'
          return false if value == 'false'
          return value.to_i if value.match?(/\A-?\d+\z/)
          return value.to_f if value.match?(/\A-?\d+\.\d+\z/)

          value
        end
      end
    end
  end
end
