# frozen_string_literal: true

require 'spec_helper'

RSpec.describe XZST::Commands::VersionCommand do
  describe '#call' do
    subject(:result) { described_class.new.call([], {}) }

    it 'returns success' do
      expect(result).to be_success
    end

    it 'includes version' do
      expect(result.data[:version]).to eq(XZST::VERSION)
    end

    it 'includes ruby version' do
      expect(result.data[:ruby]).to eq(RUBY_VERSION)
    end

    it 'includes the project name' do
      expect(result.data[:name]).to eq('xzst')
    end

    it 'includes fledge availability' do
      expect(result.data).to have_key(:fledge)
    end

    it 'includes specsync availability' do
      expect(result.data).to have_key(:specsync)
    end
  end
end
