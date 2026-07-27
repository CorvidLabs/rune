# frozen_string_literal: true

module Rune
  module Parsers
    class KeyValueParser
      KEY_VALUE_REGEX = /\A\s*([a-zA-Z0-9_\-\s]+?)\s*[:=]\s*(.*?)\s*\z/

      class << self
        def parse(text)
          return {} if text.nil? || text.strip.empty?

          result = {}
          text.each_line do |line|
            line = line.strip
            next if line.empty? || line.start_with?('#', '//')

            next unless (match = line.match(KEY_VALUE_REGEX))

            key = match[1].strip.downcase.gsub(/\s+/, '_').to_sym
            value = match[2].strip
            result[key] = coerce_value(value)
          end
          result
        end

        private

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
