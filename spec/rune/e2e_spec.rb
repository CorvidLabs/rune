# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'rune binary E2E' do
  let(:bin_path) { File.expand_path('../../bin/rune', __dir__) }

  it 'runs version command in piped mode (defaults to JSON)' do
    output = `ruby #{bin_path} version`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:status]).to eq('ok')
    expect(parsed[:data][:name]).to eq('rune')
  end

  it 'runs version command in JSON mode' do
    output = `ruby #{bin_path} version --json`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:status]).to eq('ok')
    expect(parsed[:data][:name]).to eq('rune')
  end

  it 'runs version command in NDJSON mode' do
    output = `ruby #{bin_path} version --ndjson`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:event]).to eq('result')
    expect(parsed[:status]).to eq('ok')
  end

  it 'executes git status via rune run in JSON mode' do
    output = `ruby #{bin_path} run --json git status`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:status]).to eq('ok')
    expect(parsed[:data][:command]).to eq('git status')
    expect(parsed[:data][:clean_output]).to match(/On branch|HEAD detached|nothing to commit/)
  end
end
