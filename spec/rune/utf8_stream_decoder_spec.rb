# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::UTF8StreamDecoder do
  describe '#decode' do
    it 'preserves a valid multi-byte character split across chunks' do
      decoder = described_class.new

      expect(decoder.decode("before \xF0\x9F".b)).to eq('before ')
      expect(decoder.decode("\x98\x80 after".b)).to eq('😀 after')
      expect(decoder.finish).to eq('')
    end

    it 'scrubs invalid bytes without delaying later valid text' do
      decoder = described_class.new

      expect(decoder.decode("\xFFvalid".b)).to eq('�valid')
    end

    it 'scrubs an incomplete trailing sequence when the stream finishes' do
      decoder = described_class.new

      expect(decoder.decode("\xF0\x9F".b)).to eq('')
      expect(decoder.finish).to eq('�')
    end
  end
end
