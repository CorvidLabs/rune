# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Script do
  describe '.define' do
    it 'records script steps cleanly' do
      script = described_class.define do
        wait_for(/Select a plugin/)
        send_keys "q\n"
        pause 0.5
      end

      expect(script.steps.size).to eq(3)
      expect(script.steps[0].type).to eq(:wait_for)
      expect(script.steps[0].payload).to eq(/Select a plugin/)
      expect(script.steps[1].type).to eq(:send_keys)
      expect(script.steps[1].payload).to eq("q\n")
      expect(script.steps[2].type).to eq(:pause)
      expect(script.steps[2].payload).to eq(0.5)
    end
  end

  describe '.new' do
    it 'accepts a block directly, identically to .define' do
      script = described_class.new do
        wait_for(/Select a plugin/)
        send_keys "q\n"
      end

      expect(script.steps.size).to eq(2)
      expect(script.steps[0].type).to eq(:wait_for)
      expect(script.steps[1].type).to eq(:send_keys)
    end

    it 'still works with no block, producing an empty script' do
      script = described_class.new
      expect(script.steps).to eq([])
    end
  end
end
