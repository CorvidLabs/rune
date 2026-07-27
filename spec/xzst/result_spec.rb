# frozen_string_literal: true

require 'spec_helper'

RSpec.describe XZST::Result do
  describe '.success' do
    subject(:result) { described_class.success({ version: '1.0' }) }

    it 'is successful' do
      expect(result).to be_success
    end

    it 'is not a failure' do
      expect(result).not_to be_failure
    end

    it 'has exit code 0' do
      expect(result.exit_code).to eq 0
    end

    it 'carries the data' do
      expect(result.data).to eq({ version: '1.0' })
    end
  end

  describe '.failure' do
    subject(:result) { described_class.failure('something broke') }

    it 'is a failure' do
      expect(result).to be_failure
    end

    it 'is not successful' do
      expect(result).not_to be_success
    end

    it 'has exit code 1' do
      expect(result.exit_code).to eq 1
    end

    it 'carries the error message' do
      expect(result.error).to eq 'something broke'
    end
  end

  describe '#to_h' do
    it 'serializes success results' do
      result = described_class.success({ count: 42 })
      expect(result.to_h).to eq({ status: 'ok', data: { count: 42 } })
    end

    it 'serializes failure results' do
      result = described_class.failure('oops')
      expect(result.to_h).to eq({ status: 'error', error: 'oops' })
    end
  end
end
