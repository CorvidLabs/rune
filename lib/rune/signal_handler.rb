# frozen_string_literal: true

module Rune
  class SignalHandler
    class << self
      # Traps INT/TERM for the duration of the block and yields a zero-arg
      # `forward` callable the caller can invoke as often as it likes: the
      # first call after a trapped signal arrives forwards it to pid via
      # Process.kill and every call after that is a no-op. The trap itself
      # only records which signal arrived; it never calls Process.kill
      # directly. Calling Process.kill from inside a Signal.trap handler
      # while the main thread is blocked in a native read (e.g. PTYRunner's
      # read loop) does not reliably reach the target process on every
      # Ruby/platform combination, even though the trap fires and the PID is
      # correct. Forwarding from ordinary code, outside the trap, is
      # reliable, so PTYRunner polls this callable between reads instead.
      def with_traps(pid)
        pending = nil
        forwarded = false
        old_int = trap_signal('INT') { pending = 'INT' }
        old_term = trap_signal('TERM') { pending = 'TERM' }
        yield(-> { forwarded ||= forward(pid, pending) })
      ensure
        restore_signal('INT', old_int)
        restore_signal('TERM', old_term)
      end

      private

      def forward(pid, sig)
        return false unless sig

        Process.kill(sig, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        true
      end

      def trap_signal(sig, &)
        Signal.trap(sig, &)
      rescue StandardError
        nil
      end

      def restore_signal(sig, old_handler)
        Signal.trap(sig, old_handler || 'DEFAULT')
      rescue StandardError
        nil
      end
    end
  end
end
