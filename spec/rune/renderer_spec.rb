# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Renderer do
  let(:io) { StringIO.new }

  describe 'agent mode (JSON)' do
    subject(:renderer) { described_class.new(io:, json_mode: true) }

    it 'outputs JSON for success results' do
      result = Rune::Result.success({ name: 'rune' })
      renderer.render(result)
      parsed = JSON.parse(io.string, symbolize_names: true)
      expect(parsed[:status]).to eq('ok')
      expect(parsed[:data][:name]).to eq('rune')
    end

    it 'outputs JSON for failure results' do
      result = Rune::Result.failure('bad input')
      renderer.render(result)
      parsed = JSON.parse(io.string, symbolize_names: true)
      expect(parsed[:status]).to eq('error')
      expect(parsed[:error]).to eq('bad input')
    end

    it 'reports agent mode' do
      expect(renderer).to be_agent_mode
    end
  end

  describe 'ndjson mode (streaming JSON lines)' do
    subject(:renderer) { described_class.new(io:, ndjson_mode: true) }

    it 'outputs NDJSON event lines' do
      result = Rune::Result.success({ status: 'active' })
      renderer.render(result)
      parsed = JSON.parse(io.string, symbolize_names: true)
      expect(parsed[:event]).to eq('result')
      expect(parsed[:status]).to eq('ok')
    end

    it 'renders custom events' do
      renderer.render_event(:progress, { percent: 50 })
      parsed = JSON.parse(io.string, symbolize_names: true)
      expect(parsed[:event]).to eq('progress')
      expect(parsed[:percent]).to eq(50)
    end
  end

  describe 'human mode' do
    let(:tty_io) do
      io = StringIO.new
      allow(io).to receive(:tty?).and_return(true)
      io
    end

    subject(:renderer) { described_class.new(io: tty_io, json_mode: false) }

    it 'uses custom human block when provided' do
      result = Rune::Result.success({ greeting: 'hello' })
      renderer.render(result, human_block: ->(data, out) { out.puts "Hi: #{data[:greeting]}" })
      expect(tty_io.string).to include('Hi: hello')
    end

    it 'shows error with marker for failures' do
      result = Rune::Result.failure('something went wrong')
      renderer.render(result)
      expect(tty_io.string).to include('something went wrong')
    end
  end
end
