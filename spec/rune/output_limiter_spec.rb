# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::OutputLimiter do
  describe '.truncate_middle' do
    it 'leaves text at or under the budget untouched and reports zero omitted bytes' do
      text = 'a' * 100
      result, omitted = described_class.truncate_middle(text, 100)

      expect(result).to eq(text)
      expect(omitted).to eq(0)
    end

    it 'keeps the head and tail and omits exactly the middle for over-budget text' do
      text = ('a' * 50) + ('b' * 50) + ('c' * 50)
      result, omitted = described_class.truncate_middle(text, 60)

      expect(result.delete_prefix('a' * 30).delete_suffix('c' * 30))
        .to eq(described_class.elision_marker(omitted))
      expect(omitted).to eq(text.bytesize - 60)
    end

    # The join is not an excerpt: splicing a head onto a tail produces text that
    # was never printed. Measured, a 201-byte transcript at 200 dropped the one
    # byte that made `chsh -s /bin/zsh` into `chsh -s bin/zsh` — a different,
    # still-plausible path — and the metadata said so while the text did not.
    it 'marks the join, in the text, with the exact number of bytes it dropped' do
      text = "#{'x' * 92}chsh -s /bin/zsh#{'y' * 93}"
      result, omitted = described_class.truncate_middle(text, 200)

      expect(result).to match(described_class::ELISION_PATTERN)
      expect(result[described_class::ELISION_PATTERN, 1].to_i).to eq(omitted)
      expect(result).not_to include('chsh -s bin/zsh')
    end

    it 'says "1 byte" rather than "1 bytes" when a single byte went missing' do
      result, = described_class.truncate_middle('a' * 101, 100)

      expect(result).to include('1 byte omitted')
    end

    # The budget bounds the child's output; the marker is rune's annotation of
    # the cut, not output, so it is not charged against it. That is not a new
    # kind of overshoot — `scrub` has returned 62 bytes for a budget of 60 since
    # the flag shipped, whenever both cuts split a multi-byte character.
    it 'keeps exactly max_bytes of the original text, with the marker on top' do
      text = 'a' * 500
      result, = described_class.truncate_middle(text, 60)

      expect(result.sub(described_class.elision_marker(440), '').bytesize).to eq(60)
    end

    it 'still marks the cut when the budget is smaller than the marker itself' do
      result, omitted = described_class.truncate_middle('hello world', 1)

      expect(result).to match(described_class::ELISION_PATTERN)
      expect(omitted).to eq(10)
    end

    it 'scrubs a multi-byte UTF-8 character instead of corrupting it at the cut boundary' do
      text = ('x' * 10) + ('é' * 10) + ('y' * 10) # é is 2 bytes in UTF-8
      result, = described_class.truncate_middle(text, 21) # odd budget forces an uneven split

      expect(result).to be_valid_encoding
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'handles an empty string' do
      result, omitted = described_class.truncate_middle('', 10)

      expect(result).to eq('')
      expect(omitted).to eq(0)
    end
  end

  # Both cut boundaries can land inside an escape sequence. GNU screen and pyte
  # agree on what each half then does: fed `A31mBBB` — what is left of a sliced
  # `\e[1;31m` — both display `A31mBBB`, and fed `C\e]0;titleDDD` — a head that
  # kept an OSC introducer and lost its terminator — both display `C` alone and
  # swallow `DDD`. So an untrimmed head eats the marker and the start of the
  # tail, and an unresynced tail prints control bytes as text.
  describe '.truncate_middle escape-sequence boundaries' do
    it 'trims a CSI the head cut in half rather than leaving it to swallow the marker' do
      text = "red \e[1;31mtext, and then a good deal more text to push the cut along"
      result, = described_class.truncate_middle(text, 20)

      expect(result).to start_with("red \n[rune] ====")
    end

    # `strip_ansi` treats OSC as everything up to the terminator, so a head
    # ending mid-`\e]0;title` swallowed the marker and the start of the tail with
    # it: the marker vanished from clean_output and real output went with it.
    it 'trims an OSC the head cut in half, so the marker survives strip_ansi' do
      text = "prompt \e]0;user@host: ~/proj#{'X' * 40}still-here\a done"
      result, = described_class.truncate_middle(text, 30)

      expect(Rune::Parsers::TextSanitizer.strip_ansi(result)).to match(described_class::ELISION_PATTERN)
    end

    # A 40-byte budget puts the tail cut three bytes into the seven-byte
    # `\e[1;31m`, so what the old code kept began `31mred` — the same class of
    # junk `ScreenRenderer#resync` already removes from the rendered screen.
    it 'skips exactly the remainder of a sequence the tail cut in half, and no more' do
      text = "#{'p' * 40}\e[1;31mred text follows!"
      result, omitted = described_class.truncate_middle(text, 40)

      expect(result).to end_with('red text follows!')
      expect(result).not_to include('31mred')
      expect(omitted).to eq(text.bytesize - 40 + 3) # the three bytes of `31m`
    end

    # A cut can land between the ESC and the backslash of the ST that closes a
    # DCS. Removing the trailing bare ESC alone leaves `\ePzz`, an opener with no
    # terminator, which `strip_ansi` cannot match and so prints as `Pzz`.
    it 'walks the head back past a string terminator it split, not just past the ESC' do
      text = "head\ePzz\e\\#{'t' * 40}"
      result, = described_class.truncate_middle(text, 20)

      expect(Rune::Parsers::TextSanitizer.strip_ansi(result)).to start_with("head\n[rune] ====")
    end

    it 'leaves plain text alone: no ESC means no trim and no resync' do
      text = (1..200).map { |n| "line #{n}\n" }.join
      _, omitted = described_class.truncate_middle(text, 300)

      expect(omitted).to eq(text.bytesize - 300)
    end

    # A stray `\e]` with no terminator anywhere would otherwise make every byte
    # after it look like string content: before CR and LF were excluded from a
    # control string's body, one such introducer let the head trim drop 3,197
    # bytes of ordinary output.
    it 'does not treat a multi-line run of plain text as an unterminated control string' do
      text = "before\e]#{(['tail text that is really output'] * 200).join("\n")}"
      _, omitted = described_class.truncate_middle(text, 400)

      expect(omitted - (text.bytesize - 400)).to be <= 40
    end

    it 'never removes more than the resync window, whatever the cut lands in' do
      text = "\e]#{'z' * 5000}"
      _, omitted = described_class.truncate_middle(text, 200)

      expect(omitted - (text.bytesize - 200)).to be <= (2 * described_class::RESYNC_WINDOW_BYTES)
    end
  end

  describe '.tail_lines' do
    it 'leaves text with fewer lines than the limit untouched and reports zero omitted lines' do
      text = "one\ntwo\nthree"
      result, omitted = described_class.tail_lines(text, 5)

      expect(result).to eq(text)
      expect(omitted).to eq(0)
    end

    it 'keeps only the last N lines and reports the omitted line count' do
      text = "one\ntwo\nthree\nfour\nfive"
      result, omitted = described_class.tail_lines(text, 2)

      expect(result).to eq("four\nfive")
      expect(omitted).to eq(3)
    end

    it 'preserves a trailing newline when the source had one' do
      text = "one\ntwo\nthree\n"
      result, omitted = described_class.tail_lines(text, 2)

      expect(result).to eq("two\nthree\n")
      expect(omitted).to eq(1)
    end

    it 'does not count a trailing newline as an extra empty line' do
      text = "one\ntwo\n"
      result, omitted = described_class.tail_lines(text, 2)

      expect(result).to eq(text)
      expect(omitted).to eq(0)
    end

    it 'handles an empty string' do
      result, omitted = described_class.tail_lines('', 5)

      expect(result).to eq('')
      expect(omitted).to eq(0)
    end
  end
end
