# frozen_string_literal: true

module Rune
  class SignalHandler
    class << self
      def with_traps(pid)
        old_int = trap_signal('INT', pid)
        old_term = trap_signal('TERM', pid)
        yield
      ensure
        restore_signal('INT', old_int)
        restore_signal('TERM', old_term)
      end

      private

      def trap_signal(sig, pid)
        Signal.trap(sig) { kill_pid(pid, sig) }
      rescue StandardError
        nil
      end

      def restore_signal(sig, old_handler)
        Signal.trap(sig, old_handler || 'DEFAULT')
      rescue StandardError
        nil
      end

      def kill_pid(pid, sig)
        Process.kill(sig, pid)
      rescue SystemCallError
        nil
      end
    end
  end
end
