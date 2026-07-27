# frozen_string_literal: true

require_relative 'text_sanitizer'

module Rune
  module Parsers
    class PromptDetector
      PROMPT_PATTERNS = [
        %r{\[[yY]/[nN]\]\s*\z},
        %r{\(y/n\)\??\s*\z}i,
        /\A\s*(?:Password|Passphrase|Select|Choice|Confirm):\s*\z/i,
        /\?\s+[A-Z0-9]/i,
        /\A\s*[➜❯›]/,
        %r{\A\s*[\w@:~./\-()|+ \t]+[>$%#❯›➜]\s*\z},
        /[>$%#❯›➜]\s*\z/
      ].freeze

      FALSE_POSITIVES = [
        /\A\s*>.*<.*>/,
        /\bif\b\s+.*[<>]/,
        /\b\w+\s*=\s*.*\$/,
        /\A\s*#\s+[A-Z]/i
      ].freeze

      class << self
        def detect?(line)
          return false if line.nil? || line.strip.empty?

          clean = TextSanitizer.strip_ansi(line)
          return false if FALSE_POSITIVES.any? { |fp| clean.match?(fp) }

          PROMPT_PATTERNS.any? { |pattern| clean.match?(pattern) }
        end
      end
    end
  end
end
