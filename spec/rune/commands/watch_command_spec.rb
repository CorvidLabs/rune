# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Rune::Commands::WatchCommand do
  describe '#call' do
    it 'returns failure when no command is provided' do
      result = described_class.new.call([], {})
      expect(result).to be_failure
      expect(result.error).to include('No command specified')
    end

    it 'extracts --log=PATH and opens it for the event log, forwarding the rest as the command' do
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

    it 'defaults to stderr for the event log when --log is not given' do
      watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.success({ exit_code: 0 }))
      allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

      described_class.new.call(%w[-- echo hi], {})

      expect(Rune::PTYWatcher).to have_received(:new).with(%w[echo hi], log: $stderr)
    end

    it 'preserves a literal -- inside the wrapped command, same as RunCommand' do
      watcher = instance_double(Rune::PTYWatcher, watch: Rune::Result.success({ exit_code: 0 }))
      allow(Rune::PTYWatcher).to receive(:new).and_return(watcher)

      described_class.new.call(%w[-- cargo clippy --tests -- -D warnings], {})

      expect(Rune::PTYWatcher).to have_received(:new).with(%w[cargo clippy --tests -- -D warnings], log: $stderr)
    end
  end

  describe '#human_render' do
    it 'prints a short closing summary with the exit code' do
      io = StringIO.new
      described_class.new.human_render({ exit_code: 3 }, io)
      expect(io.string).to include('exit 3')
    end
  end
end
