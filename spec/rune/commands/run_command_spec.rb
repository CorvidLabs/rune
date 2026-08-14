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

    it "preserves a literal -- that belongs to the wrapped command's own argv " \
       '(e.g. `cargo clippy --tests -- -D warnings`), stripping only rune\'s own leading separator' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[-- cargo clippy --tests -- -D warnings], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[cargo clippy --tests -- -D warnings])
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

    it 'accepts a --max-output flag and forwards it to PTYRunner' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[--max-output=1024 -- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi], max_output_bytes: 1024)
    end

    it 'accepts a --tail flag and forwards it to PTYRunner' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[--tail=20 -- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi], tail_lines: 20)
    end

    it 'combines --timeout with --max-output in the same invocation' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[--timeout=5 --max-output=1024 -- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi], timeout_seconds: 5, max_output_bytes: 1024)
    end

    it 'rejects combining --max-output and --tail in the same invocation' do
      result = described_class.new.call(%w[--max-output=1024 --tail=20 -- echo hi], {})
      expect(result).to be_failure
      expect(result.error).to include('Cannot combine --max-output and --tail')
    end

    %w[0 -5 abc 3.5].each do |bad_value|
      it "rejects --max-output=#{bad_value} instead of silently leaking it into the command" do
        result = described_class.new.call(["--max-output=#{bad_value}", '--', 'echo', 'hi'], {})
        expect(result).to be_failure
        expect(result.error).to include('Invalid --max-output value')
      end

      it "rejects --tail=#{bad_value} instead of silently leaking it into the command" do
        result = described_class.new.call(["--tail=#{bad_value}", '--', 'echo', 'hi'], {})
        expect(result).to be_failure
        expect(result.error).to include('Invalid --tail value')
      end
    end

    it 'accepts --separate-streams and forwards it to PTYRunner' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[--separate-streams -- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi], separate_streams: true)
    end

    it 'combines --timeout with --separate-streams in the same invocation' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[--timeout=5 --separate-streams -- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi], timeout_seconds: 5, separate_streams: true)
    end

    it 'does not forward separate_streams to PTYRunner when the flag is not given' do
      runner = instance_double(Rune::PTYRunner, run: Rune::Result.success({}))
      allow(Rune::PTYRunner).to receive(:new).and_return(runner)

      described_class.new.call(%w[-- echo hi], {})

      expect(Rune::PTYRunner).to have_received(:new).with(%w[echo hi])
    end
  end

  describe '#human_render' do
    let(:io) { StringIO.new }

    it 'shows a success icon, the command, duration, and exit code for exit_code 0' do
      described_class.new.human_render(
        { exit_code: 0, command: 'echo hi', duration_ms: 12.5, clean_output: "hi\n" }, io
      )
      output = Rune::Parsers::TextSanitizer.strip_ansi(io.string)
      expect(output).to include('echo hi').and include('12.5ms').and include('exit 0').and include('hi')
    end

    it 'shows a failure icon (distinct from success) for a non-zero exit_code' do
      described_class.new.human_render(
        { exit_code: 1, command: 'false', duration_ms: 3.0, clean_output: '' }, io
      )
      success_io = StringIO.new
      described_class.new.human_render({ exit_code: 0, command: 'true', duration_ms: 1.0, clean_output: '' },
                                       success_io)

      failure_icon = io.string[/\A(.*?)\e\[1m/, 1]
      success_icon = success_io.string[/\A(.*?)\e\[1m/, 1]
      expect(failure_icon).not_to eq(success_icon)
    end
  end
end
