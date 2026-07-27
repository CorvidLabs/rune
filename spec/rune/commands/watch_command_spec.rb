# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Rune::Commands::WatchCommand do
  describe '#call' do
    it 'fails clearly without touching PTYWatcher at all when stdin is not a real terminal' do
      allow(Rune::PTYWatcher).to receive(:new)

      result = described_class.new.call(%w[-- echo hi], {})

      expect(result).to be_failure
      expect(result.error).to include('requires a real terminal')
      expect(Rune::PTYWatcher).not_to have_received(:new)
    end

    it 'returns failure when no command is provided' do
      allow($stdin).to receive(:tty?).and_return(true)

      result = described_class.new.call([], {})
      expect(result).to be_failure
      expect(result.error).to include('No command specified')
    end

    it 'extracts --log=PATH and opens it for the event log, forwarding the rest as the command' do
      allow($stdin).to receive(:tty?).and_return(true)

      Dir.mktmpdir do |dir|
        log_path = File.join(dir, 'session.ndjson')
        watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.success({ exit_code: 0 }))
        allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

        described_class.new.call(["--log=#{log_path}", '--', 'echo', 'hi'], {})

        expect(Rune::PTYWatcher).to have_received(:new) do |command, log:|
          expect(command).to eq(%w[echo hi])
          expect(log).to be_a(File)
          expect(log.path).to eq(log_path)
        end
        expect(File).to exist(log_path)
      end
    end

    it 'defaults to a temp file for the event log (not stderr, which would interleave JSON ' \
       "noise into the human's live terminal view), announcing its path once" do
      allow($stdin).to receive(:tty?).and_return(true)
      watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.success({ exit_code: 0 }))
      allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

      expect { described_class.new.call(%w[-- echo hi], {}) }.to output(/rune-watch-.*\.ndjson/).to_stderr
      expect(Rune::PTYWatcher).to have_received(:new) do |command, log:|
        expect(command).to eq(%w[echo hi])
        expect(log).to be_a(File)
        expect(log.path).to include(Dir.tmpdir).and include('rune-watch-')
      end
    end

    it 'preserves a literal -- inside the wrapped command, same as RunCommand' do
      allow($stdin).to receive(:tty?).and_return(true)
      watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.success({ exit_code: 0 }))
      allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

      described_class.new.call(%w[-- cargo clippy --tests -- -D warnings], {})

      expect(Rune::PTYWatcher).to have_received(:new) do |command, log:|
        expect(command).to eq(%w[cargo clippy --tests -- -D warnings])
        expect(log).to be_a(File)
      end
    end

    it "folds the actual log path used into the returned Result's data, so human_render " \
       '(which runs on a separate Command instance, per CLI#render_result) can report it ' \
       'without relying on instance state' do
      allow($stdin).to receive(:tty?).and_return(true)

      Dir.mktmpdir do |dir|
        log_path = File.join(dir, 'session.ndjson')
        watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.success({ exit_code: 0, duration_ms: 12.3 }))
        allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

        result = described_class.new.call(["--log=#{log_path}", '--', 'echo', 'hi'], {})

        expect(result.data).to include(exit_code: 0, duration_ms: 12.3, log_path: log_path)
      end
    end

    it 'does not fold a log path into a failure result (there is nothing meaningful to attach it to)' do
      allow($stdin).to receive(:tty?).and_return(true)
      watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.failure('boom'))
      allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

      result = described_class.new.call(%w[-- echo hi], {})

      expect(result).to be_failure
      expect(result.error).to eq('boom')
    end
  end

  describe '#human_render' do
    it 'prints a closing summary with the exit code, duration, and event log path' do
      io = StringIO.new
      described_class.new.human_render({ exit_code: 0, duration_ms: 42.1, log_path: '/tmp/session.ndjson' }, io)

      expect(io.string).to include('exit 0').and include('42.1ms').and include('/tmp/session.ndjson')
    end

    it 'omits the log line when no log_path is present, without crashing' do
      io = StringIO.new
      described_class.new.human_render({ exit_code: 3, duration_ms: 5.0 }, io)

      expect(io.string).to include('exit 3')
      expect(io.string).not_to include('log:')
    end
  end
end
