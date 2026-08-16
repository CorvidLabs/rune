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
    it 'consumes colour, title and mode sequences without emitting them' do
      raw = "\e[1;32mgreen\e[0m\e]0;a title\a\e[?25l\e[?1049h"

      expect(described_class.render(raw, rows: 4, columns: 40)).to eq('green')
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
end
