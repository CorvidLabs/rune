# frozen_string_literal: true

require 'spec_helper'

RSpec.describe XZST::Renderer do
  let(:io) { StringIO.new }

  describe 'agent mode (JSON)' do
    subject(:renderer) { described_class.new(io:, json_mode: true) }

    it 'outputs JSON for success results' do
      result = XZST::Result.success({ name: 'xzst' })
      renderer.render(result)
      parsed = JSON.parse(io.string, symbolize_names: true)
      expect(parsed[:status]).to eq('ok')
      expect(parsed[:data][:name]).to eq('xzst')
    end

    it 'outputs JSON for failure results' do
      result = XZST::Result.failure('bad input')
      renderer.render(result)
      parsed = JSON.parse(io.string, symbolize_names: true)
      expect(parsed[:status]).to eq('error')
      expect(parsed[:error]).to eq('bad input')
    end

    it 'reports agent mode' do
      expect(renderer).to be_agent_mode
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
      result = XZST::Result.success({ greeting: 'hello' })
      renderer.render(result, human_block: ->(data, out) { out.puts "Hi: #{data[:greeting]}" })
      expect(tty_io.string).to include('Hi: hello')
    end

    it 'shows error with marker for failures' do
      result = XZST::Result.failure('something went wrong')
      renderer.render(result)
      expect(tty_io.string).to include('something went wrong')
    end
  end
end
