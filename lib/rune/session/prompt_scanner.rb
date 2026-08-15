# frozen_string_literal: true

require_relative '../parsers/prompt_detector'
require_relative '../parsers/text_sanitizer'

module Rune
  module Session
    # The "is the last thing on screen a prompt" rule, extracted so `PTYRunner`
    # and sessions share one definition instead of two that can drift.
    #
    # Introduced by CHG-0024 (issue #30) inside `PTYRunner`: `prompt_detected`
    # reflects whether the *last* non-blank line looks like an interactive
    # prompt, not whether any line anywhere ever did. If a process is genuinely
    # blocked on a prompt then by definition nothing arrives after it, so no
    # timing or idle-gap logic is needed.
    #
    # Note what this is NOT good for. `PromptDetector` only matches shell-shaped
    # prompts (`user@host:~$`, `[y/N]`, `Password:`, `➜`) and is deliberately
    # conservative — "prefer a rare false negative over a false positive." Agent
    # REPLs mostly present none of those shapes, so for exactly the CLIs a
    # session exists to drive this usually answers `false`. Sessions therefore
    # report it as advisory metadata and never gate a reply on it; settle-time
    # is the primary completion signal.
    module PromptScanner
      module_function

      def prompt_at_end?(text)
        return false if text.nil? || text.empty?

        last_line = Parsers::TextSanitizer.strip_ansi(text).lines.reverse_each.find { |line| !line.strip.empty? }
        return false unless last_line

        Parsers::PromptDetector.detect?(last_line)
      end
    end
  end
end
