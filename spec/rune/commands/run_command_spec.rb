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

    it 'mirrors the wrapped command exit code as the process-level exit code' do
      result = described_class.new.call(['ruby', '-e', 'exit 3'], {})
      expect(result).to be_success
      expect(result.exit_code).to eq(3)
    end

    %w[0 -5 abc 3.5].each do |bad_value|
      it "rejects --timeout=#{bad_value} instead of silently leaking it into the command" do
        result = described_class.new.call(["--timeout=#{bad_value}", '--', 'echo', 'hi'], {})
        expect(result).to be_failure
        expect(result.error).to include('Invalid --timeout value')
      end
    end

    it 'rejects an empty --timeout value' do
      result = described_class.new.call(['--timeout=', '--', 'echo', 'hi'], {})
      expect(result).to be_failure
      expect(result.error).to include('Invalid --timeout value')
    end
  end
end
