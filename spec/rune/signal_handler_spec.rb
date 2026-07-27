# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::SignalHandler do
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
  end
end
