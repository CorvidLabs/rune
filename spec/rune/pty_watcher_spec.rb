# frozen_string_literal: true

require 'spec_helper'
require 'delegate'

# A fake terminal: claims to be a tty (so PTYWatcher doesn't bail out with
# "requires a real terminal"), but has no #raw method, so PTYWatcher skips
# the real raw-mode ioctl (which would fail on a plain pipe anyway) and just
# runs the session directly. This is the seam that lets the actual
# forwarding/logging mechanics be tested without a real controlling terminal.
class FakeTerminal < SimpleDelegator
  def tty? = true
end

RSpec.describe Rune::PTYWatcher do
  def fake_writer(buffer)
    Object.new.tap do |o|
      o.define_singleton_method(:write) { |s| buffer << s }
      o.define_singleton_method(:flush) { nil }
    end
  end

  describe '#watch' do
    it 'fails clearly instead of attempting anything when stdin is not a tty' do
      result = described_class.new('echo hi', input: StringIO.new).watch
      expect(result).to be_failure
      expect(result.error).to include('requires a real terminal')
    end

    it 'fails clearly if the pty stdlib is unavailable, same as PTYRunner' do
      allow(Rune::PTYRunner).to receive(:pty_available?).and_return(false)
      result = described_class.new('echo hi', input: FakeTerminal.new(StringIO.new)).watch
      expect(result).to be_failure
      expect(result.error).to include('PTY unavailable')
    end

    it 'streams output live and forwards live input round-trip to a real interactive child' do
      human_in_r, human_in_w = IO.pipe
      log_r, log_w = IO.pipe
      output = +''

      ruby_code = <<~RUBY
        puts "Name?"
        name = $stdin.gets&.strip
        puts "Hi \#{name}!"
      RUBY

      watcher = described_class.new(
        ['ruby', '-e', ruby_code],
        log: log_w,
        input: FakeTerminal.new(human_in_r),
        output: fake_writer(output)
      )

      result_thread = Thread.new { watcher.watch }
      sleep 0.3
      human_in_w.write("Claude\n")
      result = result_thread.value
      log_w.close

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      expect(output).to include('Name?').and include('Hi Claude!')

      # Chunk boundaries aren't guaranteed to line up with logical output
      # lines (two lines can arrive in one readpartial), so assert on the
      # event shape and combined text rather than an exact chunk count.
      events = log_r.read.each_line.map { |line| JSON.parse(line) }
      expect(events.first['event']).to eq('start')
      expect(events.first).to include('command', 'pid')
      expect(events.last).to eq({ 'event' => 'exit', 'ts' => events.last['ts'], 'exit_code' => 0 })
      middle_events = events[1...-1]
      expect(middle_events).not_to be_empty
      expect(middle_events).to all(include('event' => 'output').and(include('bytes', 'text')))
      expect(middle_events.map { |e| e['text'] }.join).to include('Name?').and include('Hi Claude!')
    end

    it 'mirrors the child exit code as the process-level Result#exit_code' do
      log_r, log_w = IO.pipe
      watcher = described_class.new(
        ['ruby', '-e', 'exit 7'],
        log: log_w,
        input: FakeTerminal.new(IO.pipe.first),
        output: fake_writer(+'')
      )

      result = watcher.watch
      log_w.close
      log_r.close

      expect(result).to be_success
      expect(result.exit_code).to eq(7)
    end

    it 'wraps any other unexpected error in a generic failure instead of propagating it raw' do
      allow(PTY).to receive(:spawn).and_raise(RuntimeError, 'something truly unexpected')

      result = described_class.new('echo hi', input: FakeTerminal.new(IO.pipe.first)).watch

      expect(result).to be_failure
      expect(result.error).to include("Failed to watch command 'echo hi'").and include('something truly unexpected')
    end

    it 'ends the session cleanly (no hang) when the input source hits EOF before the child exits' do
      human_in_r, human_in_w = IO.pipe
      log_w = File.open(File::NULL, 'w') # rubocop:disable Style/FileOpen -- kept open past this line intentionally

      watcher = described_class.new('sleep 1', log: log_w, input: FakeTerminal.new(human_in_r),
                                               output: fake_writer(+''))
      result_thread = Thread.new { watcher.watch }
      sleep 0.2
      human_in_w.close # forward_input's readpartial now hits EOFError, exercising its rescue/break

      result = result_thread.value
      log_w.close

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
    end

    it 'does not crash on a wrapped command emitting non-UTF-8 bytes' do
      log_w = File.open(File::NULL, 'w') # rubocop:disable Style/FileOpen -- kept open past this line intentionally
      watcher = described_class.new(
        ['printf', '\xff\xfe\x00binary garbage\n'],
        log: log_w,
        input: FakeTerminal.new(IO.pipe.first),
        output: fake_writer(+'')
      )

      result = watcher.watch
      log_w.close

      expect(result).to be_success
    end
  end
end
