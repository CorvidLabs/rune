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

  describe '.name registration' do
    it 'registers a subclass synchronously when its CLI name is declared' do
      command_class = Class.new(described_class) { name 'spec-only-registered-command' }

      expect(Rune::CLI.commands['spec-only-registered-command']).to eq(command_class)
    end

    it 'preserves Ruby class-name reflection when .name is called without a DSL argument' do
      expect(Rune::Commands::RunCommand.name).to eq('Rune::Commands::RunCommand')
      expect(Rune::Commands::RunCommand.command_name).to eq('run')
    end

    it 'does not register a subclass that never calls .name' do
      command_class = Class.new(described_class)

      expect(Rune::CLI.commands.values).not_to include(command_class)
    end

    it 'does not leave an enabled global TracePoint for unnamed subclasses' do
      enabled_before = ObjectSpace.each_object(TracePoint).count(&:enabled?)

      6.times { Class.new(described_class) }

      expect(ObjectSpace.each_object(TracePoint).count(&:enabled?)).to eq(enabled_before)
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
