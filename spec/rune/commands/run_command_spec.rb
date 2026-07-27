# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Commands::RunCommand do
  describe '#call' do
    it 'returns failure when no command is provided' do
      result = described_class.new.call([], {})
      expect(result).to be_failure
      expect(result.error).to include('No command specified')
    end

    it 'runs provided command and returns success result' do
      result = described_class.new.call(%w[echo rune-pty-test], {})
      expect(result).to be_success
      expect(result.data[:clean_output]).to include('rune-pty-test')
    end
  end
end
