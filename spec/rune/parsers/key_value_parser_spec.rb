# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Parsers::KeyValueParser do
  describe '.parse' do
    it 'parses colon and equals separated key value text' do
      kv_text = <<~TEXT
        name: rune
        version = 0.1.0
        enabled: true
        threads: 4
      TEXT

      parsed = described_class.parse(kv_text)
      expect(parsed).to eq({
                             name: 'rune',
                             version: '0.1.0',
                             enabled: true,
                             threads: 4
                           })
    end

    it 'ignores comments and empty lines' do
      kv_text = <<~TEXT
        # Comment line
        // Another comment
        key: value
      TEXT

      parsed = described_class.parse(kv_text)
      expect(parsed).to eq({ key: 'value' })
    end
  end
end
