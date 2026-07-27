# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Command do
  describe '#call' do
    it 'raises NotImplementedError when a subclass does not override it' do
      expect { described_class.new.call([], {}) }.to raise_error(NotImplementedError, /#call must be implemented/)
    end
  end

  describe '#human_render' do
    it 'returns nil by default, signaling the Renderer to fall back to its default formatting' do
      expect(described_class.new.human_render({ foo: 'bar' }, StringIO.new)).to be_nil
    end
  end

  describe '.inherited' do
    # CLI.register defers registration to a TracePoint(:end) firing when the
    # subclass's `class ... end` body finishes executing (so `name` has had a
    # chance to run first). A real `class` keyword definition is required to
    # exercise this — Class.new(Command) { name '...' } does not emit the
    # same :end trace event and would silently fail to register.
    it 'auto-registers subclasses with CLI.commands once .name has been called' do
      class SpecOnlyRegisteredCommand < Rune::Command # rubocop:disable Lint/ConstantDefinitionInBlock
        name 'spec-only-registered-command'
      end

      expect(Rune::CLI.commands['spec-only-registered-command']).to eq(SpecOnlyRegisteredCommand)
    end

    it 'does not register a subclass that never calls .name' do
      class SpecOnlyUnnamedCommand < Rune::Command # rubocop:disable Lint/ConstantDefinitionInBlock
      end

      expect(Rune::CLI.commands.values).not_to include(SpecOnlyUnnamedCommand)
    end
  end
end
