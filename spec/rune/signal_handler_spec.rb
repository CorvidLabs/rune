# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'tmpdir'

RSpec.describe Rune::SignalHandler do
  # Sends one INT to this process and pumps the yielded forward callable until
  # it reports it actually forwarded something, so each example advances the
  # escalation ladder by exactly one rung with no reliance on sleep timing.
  # Bounded so a lost signal fails the example instead of hanging the suite.
  def deliver_one(forward_signal, signal_name: 'INT')
    Process.kill(signal_name, Process.pid)
    Timeout.timeout(5) do
      loop do
        break if forward_signal.call

        sleep 0.01
      end
    end
  end

  # A child that installs a no-op INT/TERM handler and then refuses to leave:
  # the case the escalation ladder exists for. Writes `ready_path` only after
  # its traps are installed, so an example never races the handler's setup.
  def spawn_deaf_child(ready_path)
    Process.spawn('ruby', '-e', <<~RUBY)
      Signal.trap('INT') { nil }
      Signal.trap('TERM') { nil }
      File.write(#{ready_path.inspect}, 'ready')
      sleep 30
    RUBY
  end

  def wait_for_file(path)
    Timeout.timeout(10) { sleep 0.02 until File.exist?(path) }
  end

  describe '.with_traps' do
    it 'yields a forward callable that is a no-op until a trapped signal actually arrives' do
      target_pid = Process.spawn('sleep', '5')

      described_class.with_traps(target_pid) do |forward_signal|
        expect(forward_signal.call).to be_falsy
      end

      expect(Process.kill(0, target_pid)).to eq(1)
    ensure
      Process.kill('KILL', target_pid)
      Process.wait(target_pid)
    end

    it 'forwards the caught signal to pid once, via Process.kill' do
      target_pid = Process.spawn('sleep', '5')

      described_class.with_traps(target_pid) do |forward_signal|
        Process.kill('INT', Process.pid)
        sleep 0.05 until forward_signal.call
      end

      _, status = Process.wait2(target_pid)
      expect(status.signaled?).to be true
      expect(status.termsig).to eq(Signal.list['INT'])
    end

    it 'restores the previous INT/TERM handlers after the block returns' do
      before_int = Signal.trap('INT', 'IGNORE')
      before_term = Signal.trap('TERM', 'IGNORE')

      described_class.with_traps(Process.pid) { |_forward_signal| nil }

      expect(Signal.trap('INT', before_int)).to eq('IGNORE')
      expect(Signal.trap('TERM', before_term)).to eq('IGNORE')
    ensure
      Signal.trap('INT', before_int || 'DEFAULT')
      Signal.trap('TERM', before_term || 'DEFAULT')
    end

    it 'treats forwarding to an already-dead pid as handled, not an error' do
      dead_pid = Process.spawn('true')
      Process.wait(dead_pid)

      described_class.with_traps(dead_pid) do |forward_signal|
        Process.kill('INT', Process.pid)
        sleep 0.05 until (forwarded = forward_signal.call)
        expect(forwarded).to be true
      end
    end
  end

  describe 'escalation ladder' do
    it 'forwards every trapped signal to the child, not only the first one' do
      Dir.mktmpdir do |dir|
        ready_path = File.join(dir, 'ready')
        count_path = File.join(dir, 'count')
        target_pid = Process.spawn('ruby', '-e', <<~RUBY)
          count = 0
          Signal.trap('INT') { count += 1; File.write(#{count_path.inspect}, count.to_s) }
          File.write(#{ready_path.inspect}, 'ready')
          sleep 30
        RUBY
        wait_for_file(ready_path)

        # abort_after is raised out of the way on purpose: this example is only
        # about "is signal N delivered", not about when rune gives up.
        #
        # Each round waits for the child to have *handled* signal N before
        # sending N+1. Firing three back to back instead made this example
        # flaky in a way that had nothing to do with rune: POSIX signals are
        # not queued, so two INTs landing on a sleeping child microseconds
        # apart legitimately collapse into one delivery. Acknowledging each one
        # tests forwarding rather than the OS's delivery coalescing.
        described_class.with_traps(target_pid, abort_after: 99) do |forward_signal|
          3.times do |round|
            deliver_one(forward_signal)
            Timeout.timeout(10) do
              sleep 0.02 until File.exist?(count_path) && File.read(count_path).to_i > round
            end
          end
        end

        expect(File.read(count_path)).to eq('3')
      ensure
        Process.kill('KILL', target_pid)
        Process.wait(target_pid)
      end
    end

    it 'raises Aborted on the second signal of a burst, after forwarding that signal to the child' do
      Dir.mktmpdir do |dir|
        ready_path = File.join(dir, 'ready')
        target_pid = spawn_deaf_child(ready_path)
        wait_for_file(ready_path)
        seen = 0

        expect do
          described_class.with_traps(target_pid) do |forward_signal|
            2.times do
              deliver_one(forward_signal)
              seen += 1
            end
          end
        end.to raise_error(Rune::SignalHandler::Aborted) { |error| expect(error.signal_name).to eq('INT') }

        # One completed round trip, not two: the raise happens *inside* the
        # second forward call, after Process.kill has already reached the child.
        expect(seen).to eq(1)
      ensure
        Process.kill('KILL', target_pid)
        Process.wait(target_pid)
      end
    end

    it 'escalates on a mixed INT-then-TERM burst too, reporting the signal that actually aborted' do
      Dir.mktmpdir do |dir|
        ready_path = File.join(dir, 'ready')
        target_pid = spawn_deaf_child(ready_path)
        wait_for_file(ready_path)

        expect do
          described_class.with_traps(target_pid) do |forward_signal|
            deliver_one(forward_signal, signal_name: 'INT')
            deliver_one(forward_signal, signal_name: 'TERM')
          end
        end.to raise_error(Rune::SignalHandler::Aborted) { |error| expect(error.exit_code).to eq(143) }
      ensure
        Process.kill('KILL', target_pid)
        Process.wait(target_pid)
      end
    end

    it 'treats a signal arriving after the burst window as a fresh first signal, not an escalation' do
      Dir.mktmpdir do |dir|
        ready_path = File.join(dir, 'ready')
        target_pid = spawn_deaf_child(ready_path)
        wait_for_file(ready_path)

        # Two lone interrupts minutes apart are two legitimate first signals —
        # a cumulative counter would tear rune down on the second one.
        expect do
          described_class.with_traps(target_pid, burst_window: 0.05) do |forward_signal|
            deliver_one(forward_signal)
            sleep 0.2
            deliver_one(forward_signal)
          end
        end.not_to raise_error
      ensure
        Process.kill('KILL', target_pid)
        Process.wait(target_pid)
      end
    end
  end

  describe 'Aborted' do
    it 'reports the conventional 128 + signo status for the aborting signal' do
      expect(Rune::SignalHandler::Aborted.new('INT').exit_code).to eq(130)
      expect(Rune::SignalHandler::Aborted.new('TERM').exit_code).to eq(143)
    end
  end

  describe '.reap' do
    it 'returns as soon as a child exits on its own, well inside the grace period' do
      pid = Process.spawn('true')

      status = described_class.reap(pid, grace_seconds: 5)

      expect(status.exitstatus).to eq(0)
      expect { Process.waitpid(pid) }.to raise_error(Errno::ECHILD)
    end

    it 'SIGKILLs and reaps a child that outlives the grace period instead of waiting forever' do
      Dir.mktmpdir do |dir|
        ready_path = File.join(dir, 'ready')
        pid = spawn_deaf_child(ready_path)
        wait_for_file(ready_path)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = described_class.reap(pid, grace_seconds: 0.2)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        expect(status.termsig).to eq(Signal.list['KILL'])
        expect(elapsed).to be < 5
        expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
        expect { Process.waitpid(pid) }.to raise_error(Errno::ECHILD)
      end
    end

    it 'is a no-op for a nil pid rather than raising' do
      expect(described_class.reap(nil)).to be_nil
    end

    # The defect this guards is not hypothetical and not a race: on macOS a pty
    # child SIGKILLed while bytes it wrote are still unread in the pty buffer
    # wedges permanently in the kernel's exit path (`ps` reports `?Es`) and is
    # never reapable again — a blocking Process.wait2 never returns, WNOHANG
    # polling never succeeds, and waiting minutes does not help. Draining the
    # master is the only thing that clears it. Reproduced against the real CLI,
    # which hung for over three minutes on a 20-second --timeout.
    it 'reaps a pty child that is holding unread output, given a drain block' do
      reader, _writer, pid = PTY.spawn('ruby', '-e', <<~RUBY)
        Signal.trap('INT') { $stdout.puts 'caught' }
        $stdout.sync = true
        puts 'ready'
        sleep 60
      RUBY
      reader.wait_readable(5)
      reader.readpartial(4096)
      Process.kill('INT', pid)
      sleep 0.3 # the child's reply is now sitting unread in the pty

      status = Timeout.timeout(10) do
        described_class.reap(pid, grace_seconds: 0.1) do
          reader.readpartial(4096) if reader.wait_readable(0.01)
        rescue Errno::EIO, IOError
          nil
        end
      end

      expect(status).not_to be_nil
      expect(status.termsig).to eq(Signal.list['KILL'])
      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    ensure
      reader&.close unless reader&.closed?
    end
  end

  describe 'private rescue branches (exercised directly; these never fire via real INT/TERM)' do
    it '#trap_signal swallows an invalid signal name instead of raising' do
      expect(described_class.send(:trap_signal, 'NOT_A_REAL_SIGNAL') { nil }).to be_nil
    end

    it '#restore_signal swallows an invalid signal name instead of raising' do
      expect(described_class.send(:restore_signal, 'NOT_A_REAL_SIGNAL', 'DEFAULT')).to be_nil
    end
  end
end
