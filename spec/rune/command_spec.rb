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

  describe '.usage and .flag' do
    it 'records a declared usage line and flag list for `rune <cmd> --help` to render' do
      klass = Class.new(described_class) do
        usage 'rune probe [--depth=N] [--] <target...>'
        flag '--depth=N', 'How deep to probe'
      end

      expect(klass.command_usage).to eq('rune probe [--depth=N] [--] <target...>')
      expect(klass.command_flags).to eq([{ flag: '--depth=N', description: 'How deep to probe' }])
    end

    it 'defaults to an empty flag list rather than nil, so help rendering needs no nil guard' do
      expect(Class.new(described_class).command_flags).to eq([])
    end

    it 'keeps each subclass\'s flags separate instead of accumulating them on a shared array' do
      first = Class.new(described_class) { flag '--one', 'first' }
      second = Class.new(described_class) { flag '--two', 'second' }

      expect(first.command_flags.map { |f| f[:flag] }).to eq(['--one'])
      expect(second.command_flags.map { |f| f[:flag] }).to eq(['--two'])
    end
  end

  describe 'shipped command declarations' do
    it 'gives every shipped command a usage line, so `rune <cmd> --help` is never empty' do
      shipped = Rune::CLI.commands.values.select { |k| k.to_s.start_with?('Rune::Commands::') }

      expect(shipped).to all(have_attributes(command_usage: a_string_starting_with('rune ')))
    end

    it 'documents the flags each command actually parses' do
      expect(Rune::Commands::RunCommand.command_flags.map { |f| f[:flag] }).to include('--timeout=SECONDS')
      expect(Rune::Commands::WatchCommand.command_flags.map { |f| f[:flag] }).to include('--log=PATH')
    end
  end
end
