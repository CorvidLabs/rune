# frozen_string_literal: true

module Rune
  module Session
    # One in-flight `send` and the decision of when it has been answered.
    #
    # Extracted from the supervisor because this is where the bugs kept being:
    # four rounds of review found defects here, and each fix had to be reasoned
    # about through an event loop that also owns a pty, a socket, a write queue
    # and a teardown path. Nothing here touches IO — it is given the transcript
    # slice and the facts the loop knows (the clock, whether the child is gone,
    # whether the input has actually been submitted) and returns an outcome or
    # nil for "keep waiting", which makes every rule testable on its own.
    class PendingSend
      # How long after a send a prefix-of-the-input may still be assumed to be
      # the pty's own echo. A cooked-mode echo is produced by the kernel line
      # discipline as we write, so it lands in single-digit milliseconds; this
      # is deliberately generous against load.
      ECHO_GRACE_SECONDS = 0.5
      # How long one `--wait-for-regex` match may run. Generous for any sane
      # pattern against a screenful of output, and short enough that a
      # pathological one costs a fraction of a tick rather than the session.
      REGEX_MATCH_TIMEOUT = 0.25
      # Ruby 3.0 and 3.1 have no Regexp::TimeoutError; a class that is never
      # raised keeps the rescue clause valid there without widening it.
      REGEX_TIMEOUT_ERROR = defined?(Regexp::TimeoutError) ? Regexp::TimeoutError : Class.new(StandardError)

      attr_reader :client, :cursor, :busy_at_send

      class << self
        # Bounded, because the match runs on the supervisor's only thread. A
        # pattern that backtracks catastrophically blocks inside `match?`, so the
        # loop cannot pump the pty, cannot answer `stop`, and — the part that
        # makes it worse than slow — cannot even check the send's own
        # `--timeout-ms`. Reproduced with `(a+)+\1$` against 60 a's, where the
        # send was still blocked long after its 8s deadline. Ruby memoizes most
        # textbook cases since 3.2, but that optimization is off for patterns
        # using backreferences, which is exactly the shape that got through.
        def compile_regex(source)
          return nil if source.nil? || source.empty?
          return Regexp.new(source) unless supports_regex_timeout?

          Regexp.new(source, timeout: REGEX_MATCH_TIMEOUT)
        rescue RegexpError
          nil
        end

        # Ruby 3.2 added per-Regexp timeouts, and `Regexp#timeout` with them.
        # rune still supports 3.0, where the only defence is the documented
        # limitation — and where passing an unknown keyword would be silently
        # taken as the options argument rather than rejected, so this is a
        # capability check rather than a rescue.
        def supports_regex_timeout? = Regexp.method_defined?(:timeout)
      end

      # rubocop:disable Metrics/ParameterLists -- every one of these is a distinct fact about the
      # send, all required at construction, and grouping them into an options hash would only move
      # the same list somewhere the reader cannot see it typed.
      def initialize(client:, cursor:, echo:, now:, settle_ms:, timeout_ms:, regex: nil, busy_at_send: false)
        # rubocop:enable Metrics/ParameterLists
        @client = client
        @cursor = cursor
        @echo = echo.to_s
        @settle_ms = settle_ms
        @regex = regex
        @deadline = now + (timeout_ms / 1000.0)
        @sent_at = now
        @saw_output = false
        # The child was still talking when this send landed, so what follows may
        # be the tail of the previous turn rather than a reply to this one.
        @busy_at_send = busy_at_send
      end

      # Records that something other than the pty's echo has arrived. Settling
      # additionally requires this: "never started" is a timeout, not a settle,
      # and callers who genuinely expect no reply use --no-wait.
      #
      # `now` is not optional, and passing nil here was a real bug rather than a
      # tidy default. `beyond_echo`'s partial-echo guard is written `if now &&
      # ...`, so a nil clock skipped it entirely and handed back the half-
      # arrived echo as though it were a reply. Since @saw_output latches, one
      # such tick was enough: the send then settled on the caller's own words
      # while the child was still thinking, and returned them as the answer.
      # A pty delivers a long line in several reads, so this fired whenever the
      # input was longer than one read — which is most real prompts.
      def observe(slice, now:)
        # Latched, so once true there is nothing left to learn — and this is the
        # hot path. `beyond_echo` re-scans the *whole* accumulated slice every
        # tick, so without this a large turn is quadratic: a 12MB burst the
        # child produced in 3s took the supervisor 67s to resolve, pegged at
        # 100% CPU, and a caller with a 30s timeout was told it timed out while
        # holding two thirds of a completed answer.
        return if @saw_output

        @saw_output = true unless beyond_echo(slice, now: now).strip.empty?
      end

      # The outcome for this tick, or nil to keep waiting.
      def outcome(slice, now:, child_finished:, submitted:, last_output_at:)
        # Nothing that has already arrived can be an answer to input that has
        # not been submitted yet, so while the terminator is still owed only the
        # hard limits apply. Without this a small --settle-ms, or a regex
        # matching a composer repaint, answers the send in the same tick its
        # carriage return goes out — reporting the screen as it was before the
        # child was even given the line.
        return limits(now: now, child_finished: child_finished) unless submitted

        answered(slice, now: now, child_finished: child_finished, last_output_at: last_output_at)
      end

      # The portion of a response past the pty's echo of the input.
      #
      # A pty in cooked mode echoes whatever we write straight back, so the
      # first thing to arrive after a send is our own input, not a response.
      # Counting that as "the child started answering" is the difference between
      # working and subtly broken: an agent CLI that echoes the prompt and then
      # thinks for several seconds would settle on the echo alone and hand the
      # caller its own words back.
      #
      # Characters throughout. `index` and `[]` count characters, so advancing
      # past the echo by its *byte* length overshot for any non-ASCII input — a
      # prompt containing a curly quote or an emoji silently ate the first bytes
      # of the reply.
      def beyond_echo(slice, now:)
        normalized = slice.delete("\r")
        echo = @echo.delete("\r")
        return normalized if echo.empty?

        # Located, not prefix-matched. The cursor is taken the instant we write,
        # so bytes the child was already emitting (the tail of its previous
        # prompt, a redraw) can land *before* the echo — which made a prefix
        # check fail and hand the whole slice back as if it were a reply.
        index = normalized.index(echo)
        return normalized[(index + echo.length)..].to_s if index
        # Not all there yet: treat a trailing partial echo as "still arriving",
        # but only inside the grace window, so a genuine reply that happens to
        # be a prefix of the input cannot stall the send indefinitely.
        return '' if now && within_echo_grace?(now) && echo_still_arriving?(normalized, echo)

        normalized
      end

      private

      def limits(now:, child_finished:)
        return { settled: false, timed_out: true } if now >= @deadline
        return { settled: true, child_exited: true } if child_finished

        nil
      end

      # Ordered by precedence: an explicit regex match beats the clock, the hard
      # cap beats a settle that has not happened yet, and a child that exited
      # ends the wait whatever the settle window says.
      def answered(slice, now:, child_finished:, last_output_at:)
        matched = regex_matched?(slice, now: now)
        return { settled: false, regex_timed_out: true } if matched.nil?
        return { settled: true, matched: true } if matched
        return { settled: false, timed_out: true } if now >= @deadline
        return { settled: true, child_exited: true } if child_finished
        return { settled: true } if quiet_enough?(now: now, last_output_at: last_output_at)

        nil
      end

      # True on a match, false on none, nil when the pattern exceeded its match
      # budget. Giving up on the pattern is the only sane answer: retrying it
      # next tick would spend the budget again on a slice that only grows, so
      # the send would burn the loop until its deadline instead of answering.
      #
      # Matched against the post-echo text, not the raw slice: matching the raw
      # slice meant `--wait-for-regex MARKER` on `echo MARKER` returned the
      # instant the pty echoed the command back, handing the caller its own
      # words as the "answer" before the child had produced any.
      def regex_matched?(slice, now:)
        return false unless @regex

        @regex.match?(beyond_echo(slice, now: now))
      rescue REGEX_TIMEOUT_ERROR
        nil
      end

      # True when the tail of what has arrived is the beginning of the echo,
      # i.e. the echo is mid-flight. Comparing the *whole* slice was wrong: a
      # child still printing something else when the send landed pushes the
      # partial echo off the front, so the prefix test failed and a half-arrived
      # echo counted as a reply.
      #
      # Characters, not bytes. `normalized[-length, length]` counts characters
      # while the bound was counted in bytes, so any multibyte output inside the
      # grace window — a spinner glyph, a box-drawing rule, which is most of
      # what an agent TUI paints — asked for more characters than existed and
      # got nil, and `start_with?(nil)` raised. That killed the whole supervisor
      # and took the agent CLI with it, reproducibly, within a handful of turns.
      def echo_still_arriving?(normalized, echo)
        return true if normalized.strip.empty?

        limit = [normalized.length, echo.length].min
        (1..limit).any? { |length| echo.start_with?(normalized[-length, length]) }
      end

      def within_echo_grace?(now) = (now - @sent_at) < ECHO_GRACE_SECONDS

      def quiet_enough?(now:, last_output_at:)
        return false unless @saw_output
        return false if last_output_at.nil?

        (now - last_output_at) >= (@settle_ms / 1000.0)
      end
    end
  end
end
