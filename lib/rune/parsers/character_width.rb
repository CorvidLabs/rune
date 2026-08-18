# frozen_string_literal: true

module Rune
  module Parsers
    # How many terminal columns one character occupies.
    #
    # A terminal advances the cursor by two for an East Asian Wide or Fullwidth glyph and by zero
    # for a combining mark. Counting every character as one column put an absolute column after a
    # wide run three cells early — `\e[H日本語\e[1;7HX` rendered `日本語   X` where a terminal
    # renders `日本語X` — and charged a combining mark a column of its own, so a decomposed `é`
    # took two columns and a ZWJ family emoji took three.
    #
    # The table is a curated subset of UAX #11 East_Asian_Width (W and F) plus the
    # Emoji_Presentation characters outside those blocks, and of the combining-mark ranges for zero
    # width. Deliberately not generated from the full Unicode database: rune has no runtime
    # dependencies, and a complete table is a lot of data to carry for a renderer whose job is agent
    # CLI output. What it covers is CJK, Hangul, Kana, fullwidth forms and the emoji blocks in
    # actual use; what it misses renders one column wide, which is the answer this gave for
    # everything before it existed.
    #
    # Ambiguous-width characters (UAX #11 A) are treated as narrow, which is what xterm does without
    # `-cjk_width` and the right default for a terminal not in an East Asian locale.
    module CharacterWidth
      # Below this every character is a plain single-column graphic. Checked first because agent
      # output is overwhelmingly ASCII and this runs once per character written to the grid.
      ASCII_CEILING = 0x0300

      # Nonspacing marks (Mn) and enclosing marks (Me) only, which is the `wcwidth` convention every
      # terminal follows: a *spacing* combining mark (Mc) advances the cursor and is width 1.
      #
      # The first version of this table covered Latin, Greek, Cyrillic, Hebrew, Arabic and Thai and
      # omitted every Indic script, so `हिन्दी` was charged six columns for six codepoints. A report
      # from translating the guide into Hindi framed that as "one column per codepoint", which
      # overstates it in a way worth not copying: U+093F is Mc and legitimately takes a column, so
      # zeroing every Indic mark would be as wrong in the other direction. What the fix is, is the
      # Mn/Me subset — the virama and the vowel signs written above and below.
      #
      # Terminals genuinely disagree about the *shaping* of an Indic cluster, and this does not try
      # to settle that: it follows `wcwidth`, so `हिन्दी` is five columns here and in xterm, not the
      # three a shaping engine would draw.
      ZERO = [
        0x0300..0x036F, 0x0483..0x0489, 0x0591..0x05BD, 0x0610..0x061A,
        0x064B..0x065F, 0x0670..0x0670, 0x06D6..0x06DC,
        # Devanagari, Bengali, Gurmukhi, Gujarati
        0x0900..0x0902, 0x093A..0x093A, 0x093C..0x093C, 0x0941..0x0948,
        0x094D..0x094D, 0x0951..0x0957, 0x0962..0x0963,
        0x0981..0x0981, 0x09BC..0x09BC, 0x09C1..0x09C4, 0x09CD..0x09CD, 0x09E2..0x09E3,
        0x0A01..0x0A02, 0x0A3C..0x0A3C, 0x0A41..0x0A42, 0x0A47..0x0A48,
        0x0A4B..0x0A4D, 0x0A51..0x0A51, 0x0A70..0x0A71, 0x0A75..0x0A75,
        0x0A81..0x0A82, 0x0ABC..0x0ABC, 0x0AC1..0x0AC5, 0x0AC7..0x0AC8,
        0x0ACD..0x0ACD, 0x0AE2..0x0AE3,
        # Oriya, Tamil, Telugu, Kannada, Malayalam, Sinhala
        0x0B01..0x0B01, 0x0B3C..0x0B3C, 0x0B3F..0x0B3F, 0x0B41..0x0B44,
        0x0B4D..0x0B4D, 0x0B55..0x0B56, 0x0B62..0x0B63,
        0x0B82..0x0B82, 0x0BC0..0x0BC0, 0x0BCD..0x0BCD,
        0x0C00..0x0C00, 0x0C04..0x0C04, 0x0C3E..0x0C40, 0x0C46..0x0C48,
        0x0C4A..0x0C4D, 0x0C55..0x0C56, 0x0C62..0x0C63,
        0x0C81..0x0C81, 0x0CBC..0x0CBC, 0x0CBF..0x0CBF, 0x0CC6..0x0CC6,
        0x0CCC..0x0CCD, 0x0CE2..0x0CE3,
        0x0D00..0x0D01, 0x0D3B..0x0D3C, 0x0D41..0x0D44, 0x0D4D..0x0D4D, 0x0D62..0x0D63,
        0x0D81..0x0D81, 0x0DCA..0x0DCA, 0x0DD2..0x0DD4, 0x0DD6..0x0DD6,
        0x0E31..0x0E31, 0x0E34..0x0E3A, 0x0E47..0x0E4E, 0x1AB0..0x1AFF, 0x1DC0..0x1DFF,
        0x200B..0x200F, 0x2060..0x2064, 0x20D0..0x20F0, 0xFE00..0xFE0F,
        0xFE20..0xFE2F, 0xE0100..0xE01EF
      ].freeze

      WIDE = [
        0x1100..0x115F, 0x231A..0x231B, 0x23E9..0x23EC, 0x23F0..0x23F0,
        0x23F3..0x23F3, 0x25FD..0x25FE, 0x2614..0x2615, 0x2648..0x2653,
        0x267F..0x267F, 0x2693..0x2693, 0x26A1..0x26A1, 0x26AA..0x26AB,
        0x26BD..0x26BE, 0x26C4..0x26C5, 0x26CE..0x26CE, 0x26D4..0x26D4,
        0x26EA..0x26EA, 0x26F2..0x26F3, 0x26F5..0x26F5, 0x26FA..0x26FA,
        0x26FD..0x26FD, 0x2705..0x2705, 0x270A..0x270B, 0x2728..0x2728,
        0x274C..0x274C, 0x274E..0x274E, 0x2753..0x2755, 0x2757..0x2757,
        0x2795..0x2797, 0x27B0..0x27B0, 0x27BF..0x27BF, 0x2B1B..0x2B1C,
        0x2B50..0x2B50, 0x2B55..0x2B55, 0x2E80..0x303E, 0x3041..0x33FF,
        0x3400..0x4DBF, 0x4E00..0x9FFF, 0xA000..0xA4CF, 0xA960..0xA97F,
        0xAC00..0xD7A3, 0xF900..0xFAFF, 0xFE10..0xFE19, 0xFE30..0xFE6F,
        0xFF00..0xFF60, 0xFFE0..0xFFE6, 0x1F004..0x1F004, 0x1F0CF..0x1F0CF,
        0x1F18E..0x1F18E, 0x1F191..0x1F19A, 0x1F200..0x1F2FF,
        0x1F300..0x1F64F, 0x1F680..0x1F6FF, 0x1F900..0x1F9FF,
        0x1FA70..0x1FAFF, 0x20000..0x2FFFD, 0x30000..0x3FFFD
      ].freeze

      module_function

      # Columns occupied: 0 for a combining mark, 2 for a wide glyph, 1 otherwise.
      def of(char)
        codepoint = char.ord
        return 1 if codepoint < ASCII_CEILING
        return 0 if ZERO.any? { |range| range.cover?(codepoint) }
        return 2 if WIDE.any? { |range| range.cover?(codepoint) }

        1
      rescue ArgumentError
        # An invalid byte has no codepoint. Raising here would take the supervisor down with it —
        # the transcript is scrubbed, but a caller may render raw bytes.
        1
      end
    end
  end
end
