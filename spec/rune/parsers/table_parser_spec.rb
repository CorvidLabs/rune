# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Parsers::TableParser do
  describe '.parse' do
    it 'parses space-delimited table' do
      table_text = <<~TABLE
        NAME           STATUS   VERSION
        fledge-plugin  active   1.0.0
        rust-cli       ready    2.1.0
      TABLE

      parsed = described_class.parse(table_text)
      expect(parsed.size).to eq(2)
      expect(parsed[0]).to eq({ name: 'fledge-plugin', status: 'active', version: '1.0.0' })
      expect(parsed[1]).to eq({ name: 'rust-cli', status: 'ready', version: '2.1.0' })
    end

    it 'parses pipe-delimited markdown table' do
      table_text = <<~TABLE
        | Name | Type | Description |
        |---|---|---|
        | CLI | class | Router |
        | Result | class | Response container |
      TABLE

      parsed = described_class.parse(table_text)
      expect(parsed.size).to eq(2)
      expect(parsed[0]).to eq({ name: 'CLI', type: 'class', description: 'Router' })
    end

    it 'handles multi-word column headers' do
      table_text = <<~TABLE
        CONTAINER ID   IMAGE           CREATED AT
        a1b2c3d4e5f6   nginx:latest    2 hours ago
      TABLE

      parsed = described_class.parse(table_text)
      expect(parsed.size).to eq(1)
      expect(parsed[0]).to eq({ container_id: 'a1b2c3d4e5f6', image: 'nginx:latest', created_at: '2 hours ago' })
    end

    it 'handles ragged tables with missing trailing columns' do
      table_text = <<~TABLE
        NAME           STATUS   VERSION
        fledge-plugin  active
        rust-cli       ready    2.1.0
      TABLE

      parsed = described_class.parse(table_text)
      expect(parsed.size).to eq(2)
      expect(parsed[0]).to eq({ name: 'fledge-plugin', status: 'active', version: '' })
      expect(parsed[1]).to eq({ name: 'rust-cli', status: 'ready', version: '2.1.0' })
    end

    it 'handles cell values overflowing standard column positions' do
      table_text = <<~TABLE
        NAME      STATUS   VERSION
        fledge-plugin-with-an-extremely-long-name-overflowing  active   1.0.0
        rust-cli  ready    2.1.0
      TABLE

      parsed = described_class.parse(table_text)
      expect(parsed.size).to eq(2)
      expect(parsed[0][:name]).to eq('fledge-plugin-with-an-extremely-long-name-overflowing')
      expect(parsed[0][:status]).to eq('active')
      expect(parsed[0][:version]).to eq('1.0.0')
    end

    it 'returns empty array for empty input' do
      expect(described_class.parse('')).to eq([])
    end
  end
end
