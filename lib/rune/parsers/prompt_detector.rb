# frozen_string_literal: true

require_relative 'text_sanitizer'

module Rune
  module Parsers
    class PromptDetector
      # Positive matches only. There is deliberately no "any trailing #>$%"
      # catch-all: ordinary markdown, comments, and progress lines must not be
      # treated as interactive prompts. Prefer a rare false negative over a
      # false positive that steers an agent into the wrong branch.
      PROMPT_PATTERNS = [
        %r{\[[yY]/[nN]\]\s*\z},
        %r{\(y/n\)\??\s*\z}i,
        /\A\s*(?:Password|Passphrase|Select|Choice|Confirm):\s*\z/i,
        /\A\s*\?\s+(?:Select|Choose|Pick|Confirm|Enter)\b/i,
        /\A\s*[➜❯›]/,
        # Recognizable shell PS1 forms only:
        #   user@host:~/path$
        #   user@host cwd %          (default macOS zsh)
        #   (venv) user@host:~$
        #   bash-5.2# / zsh-5.9% / fish>
        %r{
          \A\s*
          (?:
            (?:\([^)]*\)\s+)*
            [\w.-]+@[\w.-]+
            (?:
              :[~./\w()|+-]+
              |
              \s+[~\w./+-]+
            )?
            |
            (?:ba|z|fi|t?c)?sh(?:-[\d.]+)?
          )
          \s*[>$%\#]\s*\z
        }x
      ].freeze

      # Defensive exclusions kept for patterns that still share shape with
      # real prompts (e.g. blockquotes / comparisons near a terminator). The
      # old digit-percent and <placeholder> exclusions are gone: progress
      # lines and angle-bracket examples no longer match any positive pattern.
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
