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

    it 'accepts a --timeout flag and forwards it to PTYRunner' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[--timeout=5 -- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi], timeout_seconds: 5)
    end

    it 'does not forward a --timeout-like flag that appears after the -- separator' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[-- echo --timeout=5], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo --timeout=5])
    end
  end
end
