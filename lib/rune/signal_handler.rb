# frozen_string_literal: true

module Rune
  class SignalHandler
    # Raised out of the caller's polling loop once rune has forwarded a repeated
    # INT/TERM and has to stop itself rather than keep waiting on a child that is
    # plainly not going to leave. Carries the signal that triggered the abort so
    # the caller can report the conventional `128 + signo` status for it.
    class Aborted < StandardError
      attr_reader :signal_name

      def initialize(signal_name)
        @signal_name = signal_name
        super("Interrupted by a repeated SIG#{signal_name}")
      end

      def exit_code = 128 + Signal.list.fetch(signal_name, 0)
    end

    # Two signals further apart than this are independent first signals, not one
    # escalating burst. Without a window the count would be cumulative over the
    # whole run, so a user who interrupts a long-lived child once now and once
    # ten minutes later — two unrelated, legitimate single interrupts — would
    # have the second one tear rune down. A burst is the "I want out *now*"
    # double-tap; anything slower is a fresh first signal.
    BURST_WINDOW_SECONDS = 5.0

    # Signals within one burst that rune tolerates before tearing itself down.
    # Two, matching `timeout`/`docker run`/`ssh`: the first signal is the
    # child's to handle, the second is the human's to escape with.
    ABORT_AFTER = 2

    # Bounded grace a just-signalled child gets to exit on its own before
    # SIGKILL. Long enough for an ordinary handler to flush and leave, short
    # enough that a double Ctrl-C returns the terminal effectively immediately.
    ABORT_GRACE_SECONDS = 1.0

    # Bound on waiting for a SIGKILLed child to become reapable. There is no
    # such thing as a blocking wait here: see #reap for the macOS pty wedge
    # that makes an unbounded `Process.wait2` a real, reproducible hang.
    POST_KILL_SECONDS = 2.0

    # How often the reap loop rechecks (and drains).
    POLL_SECONDS = 0.02

    class << self
      # Traps INT/TERM for the duration of the block and yields a zero-arg
      # `forward` callable the caller polls between reads. Every trapped signal
      # is forwarded to pid — none is ever swallowed — and the second signal of
      # a burst additionally raises {Aborted} out of the poll so rune stops too.
      #
      # The trap itself only enqueues the signal name; it never calls
      # Process.kill directly. Calling Process.kill from inside a Signal.trap
      # handler while the main thread is blocked in a native read (e.g.
      # PTYRunner's read loop) does not reliably reach the target process on
      # every Ruby/platform combination, even though the trap fires and the PID
      # is correct. Forwarding from ordinary code, outside the trap, is
      # reliable, so callers poll this callable between reads instead.
      #
      # A queue rather than a single `pending` slot: two Ctrl-Cs pressed inside
      # one 0.2s poll interval used to overwrite each other, and the whole point
      # of the escalation ladder is that the *second* signal is not lost.
      def with_traps(pid, burst_window: BURST_WINDOW_SECONDS, abort_after: ABORT_AFTER)
        queue = Thread::Queue.new
        burst = { count: 0, at: nil, window: burst_window, abort_after: abort_after }
        old_int = trap_signal('INT') { queue << 'INT' }
        old_term = trap_signal('TERM') { queue << 'TERM' }
        yield(-> { drain(pid, queue, burst) })
      ensure
        restore_signal('INT', old_int)
        restore_signal('TERM', old_term)
      end

      # Reaps a signalled child: a bounded grace period to leave on its own,
      # then SIGKILL, then a bounded wait for it to become reapable. Returns
      # its status, or nil if it never became reapable inside the bounds.
      #
      # Every wait here is non-blocking-with-a-deadline, and the optional block
      # — called on every poll — is what keeps the child's pty drained while it
      # dies. Both are load-bearing on macOS, and neither is defensive
      # programming: a pty child that is SIGKILLed while bytes it wrote are
      # still sitting unread in the pty buffer wedges *permanently* in the
      # kernel's exit path. `ps` shows it as `?Es`, and from there it is never
      # reapable again — not by `Process.wait2`, not by waiting minutes, not by
      # another SIGKILL. Measured directly: a blocking `Process.wait2` in that
      # state never returns, `WNOHANG` polling never succeeds, and reading the
      # pty master unwedges the child instantly. This is exactly the shape a
      # `rune run` abort produces, because the last thing a child does on its
      # way out is usually to print something.
      def reap(pid, grace_seconds: ABORT_GRACE_SECONDS, &drain)
        return nil unless pid

        status = poll_for_exit(pid, grace_seconds, &drain)
        return status if status

        Process.kill('KILL', pid)
        poll_for_exit(pid, POST_KILL_SECONDS, &drain)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      private

      # Polls for pid's exit until the deadline, running `drain` (if given) on
      # every pass. Returns the status, or nil if the deadline passed first.
      def poll_for_exit(pid, seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        loop do
          yield if block_given?
          _, status = Process.wait2(pid, Process::WNOHANG)
          return status if status
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep POLL_SECONDS
        end
        nil
      end

      # Forwards every signal that arrived since the last poll, in order, then
      # raises once the burst hits the abort threshold. Forwarding happens
      # *before* the raise so the child still receives the signal that ends the
      # run — an agent CLI whose second Ctrl-C interrupts a turn must see it.
      def drain(pid, queue, burst)
        forwarded = false
        while (signal_name = next_signal(queue))
          forward(pid, signal_name)
          forwarded = true
          raise Aborted, signal_name if record_burst(burst) >= burst[:abort_after]
        end
        forwarded
      end

      def next_signal(queue)
        queue.pop(true)
      rescue ThreadError
        nil
      end

      # Returns the signal's position within the current burst (1 for the first).
      def record_burst(burst)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        burst[:count] = 0 if burst[:at].nil? || (now - burst[:at]) > burst[:window]
        burst[:at] = now
        burst[:count] += 1
      end

      def forward(pid, sig)
        return false unless sig

        Process.kill(sig, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        true
      end

      def trap_signal(sig, &block)
        Signal.trap(sig, &block)
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
