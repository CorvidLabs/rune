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
      # Note: a `/` inside an `-x` mode comment would close the literal, so the
      # comments below deliberately avoid it.
      ANSI_REGEX = /
        \e\[ [0-9;?<>=!]* [@-~]         # CSI, including private-parameter forms
        | \e\] [^\a\e]* (?: \a | \e\\ ) # OSC, BEL- or ST-terminated
        | \e [PX^_] [^\e]* \e\\         # DCS, SOS, PM, APC strings
        | \e [()][AB0K]                 # charset selection
        | \e [=><]                      # keypad and cursor-key modes
      /x

      class << self
        def strip_ansi(text)
          return '' if text.nil?

          text.gsub(ANSI_REGEX, '').gsub("\r\n", "\n").tr("\r", "\n")
        end
      end
    end
  end
end
