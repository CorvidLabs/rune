# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::CLI do
  describe 'version command' do
    it 'outputs version in JSON mode' do
      output = cli_json('version')
      expect(output[:status]).to eq('ok')
      expect(output[:data][:version]).to eq(Rune::VERSION)
    end
  end

  describe 'unknown command' do
    it 'returns error in JSON mode' do
      output = cli_json('nonexistent')
      expect(output[:status]).to eq('error')
      expect(output[:error]).to include('Unknown command')
    end
  end

  describe 'help' do
    it 'lists available commands in JSON mode' do
      output = cli_json('help')
      expect(output[:status]).to eq('ok')
      expect(output[:data][:commands]).to be_an(Array)
    end
  end
end
