# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Parsers::TextSanitizer do
  describe '.strip_ansi' do
    it 'strips ANSI color codes' do
      colored_text = "\e[31mRed Text\e[0m and \e[32mGreen Text\e[0m"
      expect(described_class.strip_ansi(colored_text)).to eq('Red Text and Green Text')
    end

    it 'normalizes carriage returns and newlines' do
      text_with_cr = "Line 1\r\nLine 2\rLine 3"
      expect(described_class.strip_ansi(text_with_cr)).to eq("Line 1\nLine 2\nLine 3")
    end

    it 'handles nil inputs safely' do
      expect(described_class.strip_ansi(nil)).to eq('')
    end
  end
end
