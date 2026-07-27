# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::PTYRunner do
  describe '#run' do
    it 'executes command and captures clean output and exit code' do
      runner = described_class.new('echo "Hello World"')
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      expect(result.data[:clean_output]).to include('Hello World')
      expect(result.data[:duration_ms]).to be_a(Numeric)
    end

    it 'captures non-zero exit codes' do
      runner = described_class.new('ruby -e "exit 42"')
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(42)
    end
  end
end
