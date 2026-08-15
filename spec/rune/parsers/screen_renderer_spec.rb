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

    it 'survives invalid UTF-8 in the stream' do
      expect { described_class.render("ok\xC3(\xA9", rows: 4, columns: 40) }.not_to raise_error
    end

    it 'returns an empty string for empty or nil input' do
      expect(described_class.render(nil)).to eq('')
      expect(described_class.render('')).to eq('')
    end
  end
end
