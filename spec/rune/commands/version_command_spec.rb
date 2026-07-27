# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Commands::VersionCommand do
  describe '#call' do
    subject(:result) { described_class.new.call([], {}) }

    it 'returns success' do
      expect(result).to be_success
    end

    it 'includes version' do
      expect(result.data[:version]).to eq(Rune::VERSION)
    end

    it 'includes ruby version' do
      expect(result.data[:ruby]).to eq(RUBY_VERSION)
    end

    it 'includes the project name' do
      expect(result.data[:name]).to eq('rune')
    end

    it 'includes fledge availability' do
      expect(result.data).to have_key(:fledge)
    end

    it 'includes specsync availability' do
      expect(result.data).to have_key(:specsync)
    end
  end

  describe '#human_render' do
    let(:io) { StringIO.new }
    let(:data) do
      { version: '9.9.9', ruby: '3.3.0', ruby_platform: 'arm64-darwin', fledge: true, specsync: false }
    end

    before { described_class.new.human_render(data, io) }

    it 'prints the version banner' do
      expect(Rune::Parsers::TextSanitizer.strip_ansi(io.string)).to include('rune v9.9.9')
    end

    it 'prints the Ruby version and platform' do
      expect(io.string).to include('Ruby 3.3.0 (arm64-darwin)')
    end

    it 'shows an available icon for a truthy toolchain flag' do
      expect(Rune::Parsers::TextSanitizer.strip_ansi(io.string)).to match(/fledge:\s+.*available/)
    end

    it 'shows a not-found icon for a falsy toolchain flag' do
      expect(Rune::Parsers::TextSanitizer.strip_ansi(io.string)).to match(/spec-sync:\s+.*not found/)
    end
  end
end
