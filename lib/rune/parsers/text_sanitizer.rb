# frozen_string_literal: true

module Rune
  module Parsers
    class TextSanitizer
      # Matches ANSI escape sequences (colors, cursor movements, erase line)
      ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]|\e\([B0K]/

      class << self
        def strip_ansi(text)
          return '' if text.nil?

          text.gsub(ANSI_REGEX, '').gsub("\r\n", "\n").tr("\r", "\n")
        end
      end
    end
  end
end
