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
      # Note: a `/` inside an `-x` mode comment would close the literal, so the
      # comments below deliberately avoid it.
      ANSI_REGEX = %r{
        \e\[ [0-9;?<>=!]* [@-~]         # CSI, including private-parameter forms
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
