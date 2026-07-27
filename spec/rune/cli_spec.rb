# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::CLI do
  describe 'version command' do
    it 'outputs version in JSON mode' do
      output = cli_json('version')
      expect(output[:status]).to eq('ok')
      expect(output[:data][:version]).to eq(Rune::VERSION)
    end

    it 'resolves --version to the version command' do
      output = cli_json('--version')
      expect(output[:data][:version]).to eq(Rune::VERSION)
    end

    it 'resolves -v to the version command' do
      output = cli_json('-v')
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

    it 'defaults to help when no command is given at all' do
      output = cli_json
      expect(output[:status]).to eq('ok')
      expect(output[:data][:commands]).to be_an(Array)
    end

    it 'includes every registered command with its summary' do
      output = cli_json('help')
      names = output[:data][:commands].map { |c| c[:name] }
      expect(names).to include('version', 'run', 'watch')
      expect(output[:data][:commands]).to all(include(:name, :summary))
    end
  end

  describe 'a command raising an unhandled exception' do
    # A literal `class ... end` is required for Command.inherited's
    # TracePoint(:end)-based CLI.register to actually fire — Class.new(Command)
    # { ... } does not emit the same :end trace event and would silently fail
    # to register, making this command unreachable by name.
    class SpecOnlyBoomCommand < Rune::Command # rubocop:disable Lint/ConstantDefinitionInBlock
      name 'spec-only-boom'

      def call(_args, _options) = raise 'kaboom'
    end

    it 'is caught and turned into a structured failure instead of crashing the CLI' do
      output = cli_json('spec-only-boom')
      expect(output[:status]).to eq('error')
      expect(output[:error]).to eq('kaboom')
    end
  end

  describe 'human-mode rendering (a real TTY, not piped)' do
    let(:tty_io) do
      StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
    end

    it 'renders help in human-readable form, listing commands and global flags' do
      capture_cli('help', io: tty_io)
      output = Rune::Parsers::TextSanitizer.strip_ansi(tty_io.string)
      expect(output).to include("rune v#{Rune::VERSION}").and include('Commands:')
      expect(output).to include('run').and include('--json')
    end

    it "dispatches to the matched command's own #human_render" do
      capture_cli('version', io: tty_io)
      output = Rune::Parsers::TextSanitizer.strip_ansi(tty_io.string)
      expect(output).to include("rune v#{Rune::VERSION}").and include('Ruby')
    end

    it 'falls back to help_human_render for an unknown command (no matching command instance)' do
      capture_cli('nonexistent', io: tty_io)
      # An error result with no human_block match still renders via the failure branch,
      # not a crash — Renderer#render_human handles result.failure? before human_block at all.
      expect(tty_io.string).to include('Unknown command')
    end
  end

  describe '.run' do
    it 'is the class-level entry point bin/rune actually calls, and behaves identically to #run' do
      io = StringIO.new
      expect do
        described_class.run(['version', '--json'], io: io)
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      expect(JSON.parse(io.string, symbolize_names: true)[:data][:version]).to eq(Rune::VERSION)
    end
  end
end
