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
        /\A\s*#\s+[A-Z]/i,
        # Progress output ("Building... 45%", "Downloading 100%") ends in a
        # bare "<digit>%", which the trailing [>$%#...] prompt fallback below
        # would otherwise catch. A real tcsh-style "%" prompt is preceded by
        # a hostname/path, not a digit, so this trade-off only misses the
        # rare case of a hostname ending in a digit.
        /\d%\s*\z/,
        # A line ending in a "<placeholder>" example (e.g. "Install with:
        # fledge plugins install <owner/repo>") ends in a bare ">", which the
        # trailing [>$%#...] prompt fallback below would otherwise catch —
        # found via real dogfooding (`rune run --json -- fledge plugins
        # search rune` misreported prompt_detected: true on a command that
        # ran to completion and printed no prompt at all). A real shell
        # prompt ending in ">" is never preceded by a "<...>" pair right
        # before it, so this is a safe exclusion.
        /<[^<>]+>\s*\z/
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
