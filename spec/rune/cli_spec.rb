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

      def call(_args, _options)
        raise 'kaboom'
      end
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

  describe 'global output flags' do
    it 'preserves --json after the separator for the wrapped command' do
      output = JSON.parse(
        capture_cli('run', '--', 'ruby', '-e', 'puts ARGV.inspect', '--', '--json'),
        symbolize_names: true
      )

      expect(output[:data][:clean_output]).to include('["--json"]')
    end

    it 'preserves --ndjson after the separator for the wrapped command' do
      output = JSON.parse(
        capture_cli('run', '--', 'ruby', '-e', 'puts ARGV.inspect', '--', '--ndjson'),
        symbolize_names: true
      )

      expect(output[:data][:clean_output]).to include('["--ndjson"]')
    end
  end

  # `rune --help` used to return "Unknown command: --help" with exit 1, and
  # `rune run --help` was worse: rune tried to *execute* `--help` as a program
  # in a PTY and exited 127. `--timeout` and `--log` were discoverable only
  # from specs/ and from the error you got for misusing them.
  describe 'help flags' do
    %w[--help -h].each do |flag|
      it "resolves a bare #{flag} to the command overview instead of an unknown-command error" do
        output = cli_json(flag)

        expect(output[:status]).to eq('ok')
        expect(output[:data][:commands].map { |c| c[:name] }).to include('run', 'watch', 'version')
        expect(output[:data][:global_flags].map { |f| f[:flag] }).to include('--help, -h')
      end

      it "shows a command's own usage for `rune run #{flag}` without executing anything" do
        allow(Rune::PTYRunner).to receive(:new)

        output = cli_json('run', flag)

        expect(output[:status]).to eq('ok')
        expect(output[:data][:command]).to eq('run')
        expect(output[:data][:usage]).to include('--timeout=SECONDS')
        expect(Rune::PTYRunner).not_to have_received(:new)
      end
    end

    it 'exposes the flag list as structured data so an agent can discover it without scraping text' do
      output = cli_json('run', '--help')

      expect(output[:data][:flags]).to include(
        a_hash_including(flag: '--timeout=SECONDS', description: a_string_including('30'))
      )
    end

    it 'supports `rune help <command>` as well as `rune <command> --help`' do
      expect(cli_json('help', 'watch')[:data]).to include(
        command: 'watch', usage: a_string_including('--log=PATH')
      )
    end

    it 'removes every mixed or repeated help alias before resolving the command' do
      mixed = cli_json('--help', '-h')
      repeated = cli_json('--help', '--help')

      expect(mixed[:status]).to eq('ok')
      expect(repeated[:status]).to eq('ok')
      expect(mixed[:data][:commands].map { |command| command[:name] }).to include('run')
      expect(repeated[:data][:commands].map { |command| command[:name] }).to include('run')
    end

    it 'reports a command with no flags of its own without an empty Flags section' do
      output = cli_json('version', '--help')

      expect(output[:data][:flags]).to eq([])
      expect(output[:data][:usage]).to eq('rune version')
    end

    it 'fails with exit 1 for help on a command that does not exist' do
      io = StringIO.new
      expect { described_class.new(io: io).run(['help', 'nope', '--json']) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(JSON.parse(io.string, symbolize_names: true)[:error]).to include('Unknown command')
    end

    # Same convention as --json/--ndjson (invariant 9): rune's flags stop at
    # the first separator, so a wrapped command keeps its own --help.
    it 'passes --help through to the wrapped command when it appears after the separator' do
      output = JSON.parse(
        capture_cli('run', '--', 'ruby', '-e', 'puts ARGV.inspect', '--', '--help'),
        symbolize_names: true
      )

      expect(output[:data][:clean_output]).to include('["--help"]')
    end

    # `rune run --help` resolves command_name to "run", so without the
    # help-mode guard in CLI#render_result the help payload would be handed to
    # RunCommand#human_render, which expects a PTY result and would raise on
    # data[:exit_code].
    it 'renders command help with the help renderer, not the command\'s own human_render' do
      tty_io = StringIO.new
      allow(tty_io).to receive(:tty?).and_return(true)

      expect { described_class.new(io: tty_io).run(%w[run --help]) }.to raise_error(SystemExit)

      expect(tty_io.string).to include('Usage:').and include('rune run [--timeout=SECONDS]')
    end

    it 'does not leak help rendering state when one CLI instance is reused' do
      tty_io = StringIO.new
      allow(tty_io).to receive(:tty?).and_return(true)
      cli = described_class.new(io: tty_io)

      expect { cli.run(%w[run --help]) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      tty_io.truncate(0)
      tty_io.rewind

      expect { cli.run(['version']) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      output = Rune::Parsers::TextSanitizer.strip_ansi(tty_io.string)
      expect(output).to include("rune v#{Rune::VERSION}").and include('Ruby')
    end
  end
end
