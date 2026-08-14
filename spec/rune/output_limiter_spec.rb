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

      expect(result.bytesize).to eq(60)
      expect(result).to start_with('a')
      expect(result).to end_with('c')
      expect(omitted).to eq(text.bytesize - 60)
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
