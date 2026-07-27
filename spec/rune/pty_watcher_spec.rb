# frozen_string_literal: true

require 'spec_helper'
require 'delegate'
require 'timeout'

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
      expect(result.data[:duration_ms]).to be_a(Numeric).and be > 0
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

    def type(io, bytes)
      sleep 0.3
      io.write(bytes)
    end

    def drive_demo_menu_to_confirm_and_quit(down_sequence)
      demo_path = File.expand_path('../../examples/demo_tui.rb', __dir__)
      human_in_r, human_in_w = IO.pipe
      log_w = File.open(File::NULL, 'w') # rubocop:disable Style/FileOpen -- kept open past this line intentionally
      output = +''

      watcher = described_class.new(['ruby', demo_path], log: log_w, input: FakeTerminal.new(human_in_r),
                                                         output: fake_writer(output))
      result_thread = Thread.new { watcher.watch }

      type(human_in_w, down_sequence * 2) # down, down -> selects "A yes/no confirmation"
      type(human_in_w, "\r") # Enter
      type(human_in_w, "y\n") # answer the confirm prompt (plain line input still works too)
      type(human_in_w, ' ') # press-any-key past the result before the screen clears/redraws
      type(human_in_w, down_sequence * 4) # fresh menu resets to index 0; down x4 -> "Quit"
      type(human_in_w, "\r") # Enter -> quit

      result = result_thread.value
      log_w.close
      [result, output]
    end

    it 'forwards raw CSI arrow-key escape sequences (ESC [ B) and Enter, driving ' \
       "examples/demo_tui.rb's real arrow-key selector end-to-end" do
      result, output = drive_demo_menu_to_confirm_and_quit("\e[B")

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      clean = output.gsub(/\e\[[0-9;]*[A-Za-z]/, '')
      expect(clean).to include('A yes/no confirmation').and include('Confirmed.').and include('Goodbye!')
    end

    it 'also accepts SS3 arrow-key escape sequences (ESC O B) — the "application cursor keys" ' \
       'convention some terminals send instead of CSI, which a spawned program cannot control' do
      result, output = drive_demo_menu_to_confirm_and_quit("\eOB")

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      clean = output.gsub(/\e\[[0-9;]*[A-Za-z]/, '')
      expect(clean).to include('A yes/no confirmation').and include('Confirmed.').and include('Goodbye!')
    end

    it "does not hang on a lone Escape key (not followed by a bracket sequence) in demo_tui.rb's " \
       'selector' do
      demo_path = File.expand_path('../../examples/demo_tui.rb', __dir__)
      human_in_r, human_in_w = IO.pipe
      log_w = File.open(File::NULL, 'w') # rubocop:disable Style/FileOpen -- kept open past this line intentionally
      output = +''

      watcher = described_class.new(['ruby', demo_path], log: log_w, input: FakeTerminal.new(human_in_r),
                                                         output: fake_writer(output))
      result_thread = Thread.new { watcher.watch }

      # A fixed sleep here raced the child's own ruby-process boot/require
      # time under system load, same class of flake fixed in the SIGINT
      # spec above — waiting for the menu to actually render guarantees the
      # child is blocked in the raw-mode selector before sending the key.
      Timeout.timeout(5) { sleep 0.02 until output.include?('Quit') }
      human_in_w.write("\e") # lone Escape: read_key's second getch must time out, not hang
      sleep 1.0
      human_in_w.write('q') # still responsive afterward

      # Explicit join timeout: a real hang fails this example with a clear
      # message instead of blocking the whole suite indefinitely.
      joined = result_thread.join(5)
      log_w.close

      expect(joined).not_to be_nil, 'watcher.watch hung past the 5s join timeout (lone Escape key not handled)'
      expect(result_thread.value).to be_success
    end

    it 'forwards SIGINT to the child while it is blocked in the raw-mode selector itself, not ' \
       'just in a line-buffered gets prompt' do
      demo_path = File.expand_path('../../examples/demo_tui.rb', __dir__)
      log_w = File.open(File::NULL, 'w') # rubocop:disable Style/FileOpen -- kept open past this line intentionally
      output = +''

      watcher = described_class.new(['ruby', demo_path], log: log_w, input: FakeTerminal.new(IO.pipe.first),
                                                         output: fake_writer(output))
      result_thread = Thread.new { watcher.watch }

      # A fixed sleep here raced the child's own ruby-process boot/require
      # time: under system load, the child sometimes hadn't reached its
      # `loop do ... rescue Interrupt` yet when the signal arrived, so it
      # died via Ruby's default uncaught-Interrupt exit (1) instead of the
      # expected 130 — a real, reproducible flake, not a hypothetical one.
      # Waiting for the menu to actually render guarantees the child is
      # blocked in the raw-mode selector, inside the rescue's scope, before
      # sending the signal.
      Timeout.timeout(5) { sleep 0.02 until output.include?('Quit') }
      Process.kill('INT', Process.pid)

      joined = result_thread.join(5)
      log_w.close

      expect(joined).not_to be_nil, 'watcher.watch hung past the 5s join timeout'
      result = result_thread.value
      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(130)
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
