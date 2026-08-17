# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Parsers::ScreenRenderer do
  # The difference from TextSanitizer is the whole point: stripping escapes
  # keeps every frame of every repaint, replaying them keeps only what is
  # actually on screen. Measured while dogfooding `rune session` against grok:
  # 10333 bytes of stripped output did not contain the answer the agent had just
  # given, because repaints had split it; the 1233-byte rendered screen did.
  describe 'repainted regions' do
    it 'keeps only the final state of a line the child rewrote in place' do
      raw = "#{(1..8).map { |second| "\rWorking #{second}s" }.join}\rDONE      "

      expect(described_class.render(raw, rows: 6, columns: 40)).to eq('DONE')
    end

    it 'applies cursor-up and erase-to-end-of-line rather than concatenating both versions' do
      raw = "line one\r\nline two\e[1A\rREPLACED\e[K"

      expect(described_class.render(raw, rows: 6, columns: 40)).to eq("REPLACED\nline two")
    end

    it 'reassembles an answer that repaints wrote out of order' do
      raw = "\e[HRUNE  7:41 PM\e[2;1Hnoise\e[1;1HRUNE-FC9FDFD8"

      expect(described_class.render(raw, rows: 6, columns: 40)).to start_with('RUNE-FC9FDFD8')
    end
  end

  describe 'erasing' do
    it 'clears the whole screen on ED 2 and honours the following cursor home' do
      raw = "junk everywhere\e[2J\e[Hclean slate"

      expect(described_class.render(raw, rows: 6, columns: 40)).to eq('clean slate')
    end

    # ECMA-48 erases *inclusive of the cursor cell* in both directions. Mode 1
    # excluded it, so a repainted line kept one character it should have lost.
    # Found by having grok review this file through rune.
    it 'includes the cell under the cursor when erasing back to the start of the line' do
      expect(described_class.render("ABCD\e[3G\e[1K", rows: 3, columns: 10)).to eq('   D')
    end

    it 'erases the whole line when the cursor sits on its last column' do
      expect(described_class.render("ABCD\e[4G\e[1K", rows: 3, columns: 10)).to eq('')
    end

    it 'still erases forward from the cursor inclusive on EL 0' do
      expect(described_class.render("ABCD\e[3G\e[0K", rows: 3, columns: 10)).to eq('AB')
    end

    it 'clears from the cursor to the end of the screen on ED 0' do
      raw = "first\r\nsecond\r\nthird\e[2;3H\e[0J"

      expect(described_class.render(raw, rows: 6, columns: 40)).to eq("first\nse")
    end
  end

  describe 'line discipline' do
    it 'wraps at the right margin instead of overwriting the last cell' do
      expect(described_class.render('abcdef', rows: 4, columns: 3)).to eq("abc\ndef")
    end

    it 'scrolls once output passes the last row, keeping the newest lines' do
      raw = (1..6).map { |line| "row#{line}" }.join("\r\n")

      expect(described_class.render(raw, rows: 3, columns: 20)).to eq("row4\nrow5\nrow6")
    end

    it 'moves the cursor back on backspace without deleting what follows' do
      expect(described_class.render("abc\b\bX", rows: 3, columns: 10)).to eq('aXc')
    end

    it 'advances to the next tab stop' do
      expect(described_class.render("a\tb", rows: 3, columns: 40)).to eq("a#{' ' * 7}b")
    end
  end

  # Found by having grok review this file through rune, checked against xterm
  # and ECMA-48. Every expectation below is what a real terminal produces.
  describe 'escapes that move the cursor' do
    it 'treats ESC D as index rather than printing a D' do
      expect(described_class.render("hello\eDworld", rows: 4, columns: 20)).to eq("hello\n     world")
    end

    it 'treats ESC E as next-line rather than printing an E' do
      expect(described_class.render("hello\eEworld", rows: 4, columns: 20)).to eq("hello\nworld")
    end

    it 'treats ESC M as reverse index, scrolling down at the top row' do
      expect(described_class.render("\eM*", rows: 4, columns: 20)).to eq('*')
    end

    it 'restores a saved cursor, for both DECSC/DECRC and CSI s/u' do
      expect(described_class.render("ABC\e7\r\nXXX\e8Y", rows: 4, columns: 20)).to eq("ABCY\nXXX")
      expect(described_class.render("ABC\e[s\r\nXXX\e[uY", rows: 4, columns: 20)).to eq("ABCY\nXXX")
    end

    it 'moves the row but not the column on VPA' do
      expect(described_class.render("hello\r\nworld\e[1dX", rows: 4, columns: 20)).to eq("helloX\nworld")
    end

    it 'treats vertical tab and form feed as motion, not as text' do
      expect(described_class.render("a\vb", rows: 4, columns: 20)).to eq("a\n b")
    end
  end

  # xterm defers the wrap: after the last cell the cursor stays on it, and the
  # wrap happens when the next graphic arrives. Leaving the column one past the
  # end put it in a state no terminal uses, which every relative move read wrong.
  describe 'the cursor on the last column' do
    it 'backspaces onto the last cell rather than past it' do
      expect(described_class.render("12345678\bX", rows: 4, columns: 8)).to eq('123456X8')
    end

    it 'moves left from the last cell, not from one beyond it' do
      expect(described_class.render("12345678\e[2DX", rows: 4, columns: 8)).to eq('12345X78')
    end

    it 'keeps the column across a line feed' do
      expect(described_class.render("12345678\nX", rows: 4, columns: 8)).to eq("12345678\n       X")
    end

    it 'erases to end of line from the last cell, not beyond it' do
      expect(described_class.render("12345678\e[K", rows: 4, columns: 8)).to eq('1234567')
    end

    it 'still wraps the next graphic character' do
      expect(described_class.render('abcdef', rows: 4, columns: 3)).to eq("abc\ndef")
    end
  end

  describe 'insert, delete and scroll' do
    it 'deletes characters and shifts the rest left' do
      expect(described_class.render("ABCD\e[2G\e[P", rows: 4, columns: 20)).to eq('ACD')
    end

    it 'inserts blanks and shifts the rest right' do
      expect(described_class.render("ABCD\e[2G\e[2@", rows: 4, columns: 20)).to eq('A  BCD')
    end

    it 'erases characters in place without shifting' do
      expect(described_class.render("ABCD\e[2G\e[2X", rows: 4, columns: 20)).to eq('A  D')
    end

    it 'scrolls the screen up' do
      raw = "line1\r\nline2\r\nline3\e[H\e[S"

      expect(described_class.render(raw, rows: 4, columns: 20)).to eq("line2\nline3")
    end

    it 'deletes a line and pulls the rest up' do
      raw = "line1\r\nline2\r\nline3\e[1;1H\e[M"

      expect(described_class.render(raw, rows: 4, columns: 20)).to eq("line2\nline3")
    end
  end

  describe 'sequences that cannot move the cursor' do
    # `\e[?1049h` used to be in this list and is not any more: it switches to
    # the alternate screen buffer, which is the opposite of invisible. Grouping
    # it here is what let the gap sit unnoticed — the test asserted the bug.
    it 'consumes colour, title and mode sequences without emitting them' do
      raw = "\e[1;32mgreen\e[0m\e]0;a title\a\e[?25l\e[?2004h"

      expect(described_class.render(raw, rows: 4, columns: 40)).to eq('green')
    end
  end

  # An agent CLI enters the alternate screen at startup, so without this every
  # byte printed before the switch stayed on the grid and `read --screen`
  # rendered a shell banner underneath the TUI.
  describe 'the alternate screen buffer' do
    it 'hides the primary buffer while the alternate one is in use' do
      raw = "PRIMARY\r\n\e[?1049hALT"

      frame = described_class.render(raw, rows: 4, columns: 20)

      expect(frame).to include('ALT')

      expect(frame).not_to include('PRIMARY')
    end

    it 'restores the primary buffer and discards the alternate one on exit' do
      raw = "PRIMARY\r\n\e[?1049hALT\e[?1049l"

      frame = described_class.render(raw, rows: 4, columns: 20)

      expect(frame).to include('PRIMARY')

      expect(frame).not_to include('ALT')
    end

    it 'treats a second enter as idempotent rather than saving the alternate buffer over the primary' do
      raw = "PRIMARY\r\n\e[?1049hALT1\e[?1049h\e[?1049l"

      frame = described_class.render(raw, rows: 4, columns: 20)

      expect(frame).to include('PRIMARY')

      expect(frame).not_to include('ALT1')
    end

    it 'ignores an exit that was never entered' do
      expect(described_class.render("PRIMARY\e[?1049l", rows: 4, columns: 20)).to include('PRIMARY')
    end

    # 47 and 1047 predate 1049 and carry no cursor save; that is why 1049 exists.
    [47, 1047].each do |mode|
      it "switches buffers for the older mode #{mode} without a cursor save" do
        raw = "PRIMARY\r\n\e[?#{mode}hALT\e[?#{mode}l"

        frame = described_class.render(raw, rows: 4, columns: 20)

        expect(frame).to include('PRIMARY')

        expect(frame).not_to include('ALT')
      end
    end

    it 'returns to the primary buffer on a full reset, so pre-reset output cannot reappear' do
      raw = "PRIMARY\r\n\e[?1049hALT\ecAFTER\e[?1049l"

      frame = described_class.render(raw, rows: 4, columns: 20)

      expect(frame).to include('AFTER')

      expect(frame).not_to include('PRIMARY')
    end

    it 'applies every mode in a combined set, not only the first' do
      raw = "PRIMARY\r\n\e[?25;1049hALT"

      frame = described_class.render(raw, rows: 4, columns: 20)

      expect(frame).to include('ALT')

      expect(frame).not_to include('PRIMARY')
    end
  end

  # A TUI turns autowrap off to paint the last cell of a row without scrolling
  # the screen out from under itself.
  describe 'autowrap (DECAWM)' do
    it 'does not wrap while autowrap is off' do
      expect(described_class.render("\e[?7l#{'A' * 25}", rows: 4, columns: 20).lines.length).to eq(1)
    end

    it 'wraps again once autowrap is turned back on' do
      expect(described_class.render("\e[?7l\e[?7h#{'A' * 25}", rows: 4, columns: 20).lines.length).to eq(2)
    end

    it 'wraps by default, with no mode set at all' do
      expect(described_class.render('A' * 25, rows: 4, columns: 20).lines.length).to eq(2)
    end
  end

  # Found by a review round that diffed rune against two independent emulators
  # (pyte and xterm.js headless) across streams captured from real agent CLIs.
  describe 'sequences that used to be printed as text' do
    # Anything the parser does not consume is left for PRINTABLE to match and
    # written onto the screen. This is the `ESC D` bug — fixed for three
    # escapes, still present for the rest.
    {
      "\e[2 q$ ready" => '$ ready',                       # DECSCUSR: intermediate byte
      "\e[38:2::255:0:0mERROR" => 'ERROR',                # SGR in ITU-T T.416 colon form
      "\e[0\"qb" => 'b',                                  # DECSCA
      "col\eHumn" => 'column',                            # HTS
      "a\eNb\eOc" => 'abc',                               # SS2 / SS3
      "a\e*Bb\e+Bc" => 'abc',                             # G2 / G3 designation
      "a\e%Gb" => 'ab',                                   # select UTF-8
      "a\e(1b" => 'ab'                                    # G0 designation, final outside [AB0K]
    }.each do |raw, expected|
      it "consumes #{raw.inspect} rather than printing its body" do
        expect(described_class.render(raw, rows: 6, columns: 60)).to eq(expected)
      end
    end

    # A live session's transcript ends wherever the last read landed, so a
    # stream cut mid-sequence is the normal case, not an edge one.
    it 'consumes a sequence the stream ended in the middle of' do
      expect(described_class.render("answer: 42\e[38;2;10", rows: 6, columns: 60)).to eq('answer: 42')
      expect(described_class.render("answer: 42\e]0;a title", rows: 6, columns: 60)).to eq('answer: 42')
    end
  end

  # DECSTBM. Every pager, editor and full-screen agent sets a region and then
  # relies on a line feed at its bottom to scroll. Replaying two real captured
  # transcripts, 8 of 40 rows differed from a reference emulator before this.
  describe 'scroll regions' do
    it 'scrolls at the region bottom rather than walking down the page' do
      raw = "\e[1;3r\e[1;1HA\r\nB\r\nC\r\nD\r\nE"

      expect(described_class.render(raw, rows: 10, columns: 40)).to eq("C\nD\nE")
    end

    # Confirmed against pyte rather than hand-derived: reverse index at the
    # region top scrolls the region, leaving the cursor on its top row, so `Z`
    # lands beside `X` rather than above it.
    it 'scrolls the region down on reverse index at its top' do
      raw = "\e[2;4r\e[2;1HX\r\nY\eMZ"

      expect(described_class.render(raw, rows: 10, columns: 40)).to eq("\nXZ\nY")
    end

    it 'confines insert and delete line to the region' do
      raw = "\e[1;4rA\r\nB\r\nC\r\nD\e[2;1H\e[M"

      expect(described_class.render(raw, rows: 10, columns: 40)).to eq("A\nC\nD")
    end

    it 'ignores a region whose bounds are inverted or out of range' do
      raw = "\e[5;2rA\r\nB\r\nC\r\nD"

      expect(described_class.render(raw, rows: 3, columns: 40)).to eq("B\nC\nD")
    end
  end

  # This renders untrusted child output, so an unclamped count is a denial of
  # service rather than a cosmetic bug: these raised RangeError out of .render,
  # allocated 2.9GB, or never returned.
  describe 'hostile parameter values' do
    [
      "ok\e[99999999999999999999@x",
      "ok\e[99999999999999999999Xx",
      "AB\e[999999999@C",
      "a\e[1000000L",
      "AB\e[99999999999999999999L",
      "AB\e[99999999999999999999S",
      "AB\e[9999999T"
    ].each do |raw|
      it "clamps #{raw.inspect} instead of crashing, hanging or exhausting memory" do
        expect { described_class.render(raw, rows: 40, columns: 120) }.not_to raise_error
      end
    end
  end

  describe 'erase parameters that are not defined' do
    # Both erase families used `else` as "erase everything", so an undefined
    # parameter destroyed content a real terminal leaves alone.
    it 'treats an unknown erase parameter as a no-op' do
      expect(described_class.render("KEEP THIS\e[1;1H\e[9K", rows: 6, columns: 40)).to eq('KEEP THIS')
      expect(described_class.render("KEEP THIS\e[9J", rows: 6, columns: 40)).to eq('KEEP THIS')
    end

    # CSI 3 J is "erase saved lines" — the scrollback, which this renderer does
    # not keep. `clear` emits it, and it was wiping the visible screen.
    it 'leaves the display alone on erase-saved-lines' do
      expect(described_class.render("first\r\nsecond\e[3J", rows: 6, columns: 40)).to eq("first\nsecond")
    end
  end

  # Found by a second review round, each verified against GNU screen and
  # @xterm/headless. pyte disagrees on one of these and is wrong: `\e[<u` is a
  # well-formed CSI (`<` is a parameter byte, `u` a final byte) so it must be
  # consumed whole, and pyte prints the `u`.
  describe 'control bytes and private-marker sequences' do
    it 'does not write BEL, NUL, SO, SI or DEL into the grid' do
      raw = "bell\anul\x00so\x0esi\x0fdel\x7fend"

      expect(described_class.render(raw, rows: 4, columns: 40)).to eq('bellnulsosidelend')
    end

    # `TERM=screen tput sgr0` is `\e[m\x0f\x0f`, so ncurses under tmux emitted
    # two literal cells and a two-column shift on every attribute reset.
    it 'does not shift the line on the SI pair ncurses emits with sgr0' do
      expect(described_class.render("A\e[m\x0f\x0fB", rows: 4, columns: 40)).to eq('AB')
    end

    # `?` was guarded and `<`, `>`, `=` were not, though all four are ECMA-48
    # private-prefix bytes. Across 451 real captures there were 526 private
    # `CSI u` forms and zero public ones, so restore-cursor never fired
    # correctly on real agent output — it only ever teleported the cursor.
    it 'does not run a private-marker sequence as its public namesake' do
      expect(described_class.render("L1\r\nL2\r\nL3\e[>2T", rows: 4, columns: 40)).to eq("L1\nL2\nL3")
      expect(described_class.render("AB\e[3;3HCD\e[<u", rows: 4, columns: 40)).to eq("AB\n\n  CD")
    end
  end

  # 0.8.0 gave the renderer scroll-region state, which turned two previously
  # harmless no-ops into paths that leave that state stale.
  describe 'resetting the scroll region' do
    # The trigger is someone typing `reset` or `tput init` to recover a garbled
    # agent TUI — exactly when a region is live. terminfo's rs1 for xterm is
    # `\ec` and rs2/is2 begin with `\e[!p`.
    it 'resets the region and clears the screen on RIS' do
      raw = "\e[2;3rA\r\nB\r\nC\ecX\r\nY\r\nZ\r\nQ"

      expect(described_class.render(raw, rows: 4, columns: 20)).to eq("X\nY\nZ\nQ")
    end

    # DECSTR carries an intermediate byte, so both csi_control guards rejected
    # it, and its final byte is not in CONTROLS — it was dropped twice over.
    it 'resets the region without clearing the screen on DECSTR' do
      raw = "\e[2;3rA\r\nB\r\nC\e[!pX\r\nY\r\nZ\r\nQ"

      expect(described_class.render(raw, rows: 4, columns: 20)).to eq("X\nY\nZ\nQ")
    end

    it 'prints neither escape as text' do
      expect(described_class.render("ok\ecfresh", rows: 4, columns: 20)).to eq('fresh')
    end

    # Discarding an out-of-range region leaves the PREVIOUS one in force, which
    # is worse than doing nothing now that regions exist.
    it 'clamps a region whose bottom is past the last row rather than discarding it' do
      raw = "\e[2;5r\e[3;99r\e[8;1HX\nY"

      expect(described_class.render(raw, rows: 8, columns: 20)).to eq("\n\n\n\n\n\nX\n Y")
    end
  end

  describe 'bounds' do
    it 'renders only the tail of a long transcript' do
      raw = "#{'early' * 100}\e[2J\e[Hlate"

      expect(described_class.render(raw, rows: 4, columns: 40, tail_bytes: 64)).to eq('late')
    end

    # Found by taking a census of a real agent's output: it repaints purely by
    # absolute positioning inside synchronised-update brackets and never erases
    # anything, so the stream is almost entirely escape sequences and a cut is
    # far more likely to land inside one than in text.
    it 'does not print the remainder of an escape sequence the tail cut in half' do
      suffix = "\e[?2026h\e[2;1HHELLO\e[?2026l"
      raw = ('x' * 1000) + suffix

      # Every cut lands at a different point inside the leading sequence.
      (0..6).each do |bytes_lost|
        rendered = described_class.render(raw, rows: 4, columns: 40, tail_bytes: suffix.bytesize - bytes_lost)

        expect(rendered).to eq("\nHELLO")
      end
    end

    it 'keeps text when the cut lands in a stream that has no escapes to resync on' do
      raw = "line\n" * 500

      expect(described_class.render(raw, rows: 4, columns: 40, tail_bytes: 40)).to include('line')
    end

    it 'keeps text before an escape that is further away than the resync scan' do
      # 300 bytes of text before the first escape, which is past the 256-byte
      # scan. Resyncing to it would silently discard eight rows of real output.
      raw = "#{'y' * 1000}#{'z' * 300}\e[2;1HAFTER"

      rendered = described_class.render(raw, rows: 10, columns: 40, tail_bytes: 311)

      expect(rendered).to include('z')
      expect(rendered).to include('AFTER')
    end

    it 'survives invalid UTF-8 in the stream' do
      expect { described_class.render("ok\xC3(\xA9", rows: 4, columns: 40) }.not_to raise_error
    end

    it 'returns an empty string for empty or nil input' do
      expect(described_class.render(nil)).to eq('')
      expect(described_class.render('')).to eq('')
    end
  end

  # The size now arrives from outside the process — a session records its
  # child's winsize in a JSON file and reads it back — so "absent", "not a
  # number" and "larger than any terminal" are all inputs this has to survive.
  describe '.dimensions' do
    it 'uses the defaults when no size is given' do
      expect(described_class.dimensions(nil, nil)).to eq([described_class::DEFAULT_ROWS,
                                                          described_class::DEFAULT_COLUMNS])
    end

    it 'takes a real size as given' do
      expect(described_class.dimensions(24, 80)).to eq([24, 80])
    end

    it 'accepts a size that arrived as text, which is how JSON round-trips can leave it' do
      expect(described_class.dimensions('24', '80')).to eq([24, 80])
    end

    it 'falls back for a size no terminal has' do
      expect(described_class.dimensions(0, -1)).to eq([described_class::DEFAULT_ROWS,
                                                       described_class::DEFAULT_COLUMNS])
      expect(described_class.dimensions('tall', {})).to eq([described_class::DEFAULT_ROWS,
                                                            described_class::DEFAULT_COLUMNS])
    end

    # The grid is allocated eagerly, so an unbounded dimension is an allocation
    # an untrusted file could ask for.
    it 'clamps a size past any real terminal rather than allocating it' do
      expect(described_class.dimensions(10**12, 10**12)).to eq([described_class::MAX_ROWS,
                                                                described_class::MAX_COLUMNS])
    end

    it 'renders at a caller-supplied size without raising on a nonsensical one' do
      expect(described_class.render('abcdef', rows: nil, columns: 3)).to eq("abc\ndef")
      expect(described_class.render('abcdef', rows: 4, columns: 'three')).to eq('abcdef')
    end
  end
end
