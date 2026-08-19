# frozen_string_literal: true

module Rune
  module Parsers
    class TextSanitizer
      # Matches ANSI escape sequences.
      #
      # Originally only SGR-shaped CSI (`\e[0-9;]*[a-zA-Z]`) plus a couple of
      # charset selects, which is enough for a command that merely colours its
      # output. It is nowhere near enough for a full-screen TUI: private-mode
      # switches (`\e[?1049h` alt-screen, `\e[?2026h` synchronized output),
      # OSC title strings (`\e]0;title\a`), keypad modes and cursor queries all
      # survived, so `clean_output` for a driven agent CLI was still unreadable
      # escape soup. Found by driving real agent CLIs through `rune session`,
      # where the "last line of output" summary came back as `\e[?25h`.
      # The two-byte escapes were the next gap, found the same way: driving
      # Claude Code through `rune session`, `clean_output` opened with a literal
      # `\e7\e8` (DECSC/DECRC) on every read — present uncapped as well as
      # capped, so the stripper rather than the truncation. `ScreenRenderer`
      # already acted on `[DEM78c]`, so the two parsers in this module disagreed
      # about what an escape is; the sanitizer was the one that was wrong.
      #
      # The charset branch was `[()][AB0K]` and is now the renderer's own set:
      # `\e(1` and `\e)0` are as real as `\e(B`, and a designation left behind
      # puts its final byte into the text as a stray letter.
      #
      # The CSI arm is the full ECMA-48 grammar — parameter bytes, then
      # intermediate bytes, then one final byte — because it was the narrower
      # half of the same disagreement. `ScreenRenderer::CSI` was widened to
      # admit `:` and the intermediates after a real capture of one agent
      # contained 80 sequences it printed instead of obeying; the sanitizer kept
      # the old pattern, so `\e[38:2::255:0:0m` (the ITU-T T.416 colon form of
      # truecolour SGR) and `\e[2 q` (DECSCUSR — fish, starship, zsh vi-mode,
      # Codex CLI) still survived into `clean_output`, `--grep` and `list`'s
      # `last_line` while `--screen` rendered them correctly. Two parsers in one
      # module, one fixed and one not, is the exact shape this file's history
      # already records twice.
      #
      # Note: a `/` inside an `-x` mode comment would close the literal, so the
      # comments below deliberately avoid it.
      ANSI_REGEX = %r{
        \e\[ [0-9:;?<>=!]* [ -/]* [@-~] # CSI: parameters, then intermediates, then a final byte
        | \e\] [^\a\e]* (?: \a | \e\\ ) # OSC, BEL- or ST-terminated
        | \e [PX^_] [^\e]* \e\\         # DCS, SOS, PM, APC strings
        | \e [()*+] [A-Za-z0-9<>%"&./:?-] # charset designation into G0-G3
        | \e [\#%] [@A-Za-z0-9]         # DEC screen alignment, UTF-8 select
        | \e [78DEHMNOZc=><\\]          # two-byte escapes
      }x

      class << self
        def strip_ansi(text)
          return '' if text.nil?

          text.gsub(ANSI_REGEX, '').gsub("\r\n", "\n").tr("\r", "\n")
        end
      end
    end
  end
end
