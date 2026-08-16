# frozen_string_literal: true

require 'strscan'

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
      # Everything a terminal consumes without printing: the full CSI grammar
      # (parameters, intermediates, final byte), the string sequences, charset
      # selection, and the single-byte escapes. The trailing catch-all matters
      # as much as the specific forms — an escape left behind here would be
      # counted as text by one half of the search and dropped by the other.
      ESCAPE_SEQUENCE = %r{
        \e\[ [0-9:;<>=?]* [ -/]* [@-~]
        | \e\] [^\a\e]* (?: \a | \e\\ )
        | \e [PX^_] [^\e]* \e\\
        | \e [()*+] [A-Za-z0-9<>%"&./:?-]
        | \e [%\#] [@A-Za-z0-9]
        | \e .?
      }x
      # Anything that is neither an escape nor whitespace, i.e. the characters
      # a condensed comparison keeps.
      PRINTED = /[^\s\e]+/
      # How much output is scanned for a transformed echo before the search is
      # abandoned. A repaint of one line of input costs at most a few tens of
      # KB even when the child redraws on every keystroke; past this the echo
      # is not going to be found and the scan is only costing the event loop.
      ECHO_SEARCH_LIMIT = 256 * 1024
      # How far either side of a candidate match to look for the input being
      # repainted around it, as a multiple of the input's own length. A repaint
      # carries colour and cursor sequences between the characters, so the copy
      # on the wire is several times the text it draws.
      ECHO_COPY_MARGIN = 8
      # ...and a floor under that window, so a one-word input still looks far
      # enough either side to see the copy it sits in.
      REPAINT_MARGIN_FLOOR = 256

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
        @echo = Echo.new(echo)
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
        return normalized if @echo.empty?

        beyond = @echo.beyond(normalized)
        return beyond if beyond
        # Not found yet, so nothing is offered while it might still be arriving.
        # The rule this replaces asked whether the *tail* of the slice was a
        # prefix of the input, which recognises only an echo that is verbatim
        # and unfinished. A child drawing the input into a bordered composer is
        # neither: it defeated the search above and tripped no partial test
        # either, so the whole slice — a screenful of the caller's own words —
        # went to the pattern. Reproduced end to end at 0.19s against a
        # 78-character prompt, decided purely by whether the tick landed before
        # the child's next frame.
        return '' if now && within_echo_grace?(now)

        # Past the window with nothing located, this is a child that does not
        # echo at all: ECHO is off, or it is reading raw keystrokes and drawing
        # nothing. There is no echo for the pattern to match, so withholding
        # further would only hang every send to one of them — measured: a
        # strict version of this rule failed the no-echo case outright.
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

        text = beyond_echo(slice, now: now)
        candidate_matches(text).any? { |match| !@echo.repaint?(text, match) }
      rescue REGEX_TIMEOUT_ERROR
        nil
      end

      # The first and last places the pattern matches, or none.
      #
      # Both, because they answer different failure modes. A line-oriented child
      # says its answer once and the first match is it. A full-screen child
      # redraws the whole frame — input included — many times a second, so the
      # frames after the located echo contain the input again and the *first*
      # match is a repaint; the answer, when it comes, is at the end. Taking
      # only one of the two loses one of those cases, and taking every match
      # would mean allocating one MatchData per repaint per tick.
      def candidate_matches(text)
        first = @regex.match(text)
        return [] unless first

        last = text.rindex(@regex)
        return [first] if last.nil? || last <= first.begin(0)

        [@regex.match(text, last), first].compact
      end

      def within_echo_grace?(now) = (now - @sent_at) < ECHO_GRACE_SECONDS

      def quiet_enough?(now:, last_output_at:)
        return false unless @saw_output
        return false if last_output_at.nil?

        (now - last_output_at) >= (@settle_ms / 1000.0)
      end

      # Where the pty's echo of one send's input sits in what came back.
      #
      # Its own class because "find the input in the output" turned out to be
      # the hard half of deciding when a send is answered, and because it is
      # pure text: given the same bytes it gives the same answer, with no clock,
      # no socket and no pty in the way.
      #
      # The rule it exists to enforce is that a pattern must never be satisfied
      # by the caller's own input. Everything below is one of the ways a child
      # can put that input back on the wire in a shape `index` cannot find.
      class Echo
        def initialize(text)
          @text = text.to_s.delete("\r")
          # Where the echo was found to end, once it has been found. The slice
          # only ever grows at the end, so the offset stays valid for the life
          # of the send — and every later tick is a slice rather than a scan.
          @ends_at = nil
          @condensed = nil
        end

        def empty? = @text.empty?

        # Everything past the echo, or nil when the echo has not been found.
        def beyond(normalized)
          return normalized[@ends_at..].to_s if @ends_at

          # Located, not prefix-matched. The cursor is taken the instant we
          # write, so bytes the child was already emitting (the tail of its
          # previous prompt, a redraw) can land *before* the echo — which made a
          # prefix check fail and hand the whole slice back as if it were a
          # reply.
          verbatim = normalized.index(@text)
          return normalized[(@ends_at = verbatim + @text.length)..].to_s if verbatim

          # Verbatim is the exception, not the rule. A child that *transforms*
          # the echo produces no such substring at all: python's REPL redraws
          # the line in colour on every keystroke, and readline splits the echo
          # with a space and a carriage return where it wraps the terminal
          # (measured at 120 columns: 110 characters echo as one run, 111 do
          # not). Neither is exotic, both defeated the check above, and the
          # whole slice — echo included — was then handed to the pattern, which
          # answered `matched` before the child had run a line of the input.
          transformed = locate(normalized)
          transformed && normalized[(@ends_at = transformed)..].to_s
        end

        # True when the pattern matched inside a copy of the input rather than
        # inside anything the child produced.
        #
        # The residue of the echo problem that no boundary can solve: an agent
        # TUI paints the prompt into its transcript and then repaints the whole
        # frame on every spinner tick, so the input keeps reappearing *after*
        # wherever its first copy ended. Moving the boundary to the last copy
        # instead would discard any answer printed before the next repaint —
        # measured: it fixes the two TUI cases and breaks a child that quotes
        # the request back after answering. So this asks the narrower question
        # of whether this particular match is covered by a copy of the input
        # drawn around it, and leaves the boundary where it is.
        def repaint?(text, match)
          inside = self.class.condense(match[0])
          return false if empty? || inside.empty?

          before, after = surroundings(text, match)
          covered?(before + inside + after, before.length, before.length + inside.length)
        end

        # The text with escapes and whitespace removed. Those two are exactly
        # the difference between the input and every transformed echo measured:
        # colour and cursor sequences around the characters, and a wrap or a
        # line break inserted between them.
        def self.condense(text) = text.gsub(ESCAPE_SEQUENCE, '').gsub(/\s+/, '')

        private

        # As much either side of the match as a copy of the echo could occupy,
        # condensed. Bounded so this costs the same whatever the slice has grown
        # to: it is only ever asked about one match at a time.
        def surroundings(text, match)
          margin = (@text.length * ECHO_COPY_MARGIN) + REPAINT_MARGIN_FLOOR
          [self.class.condense(text[[match.begin(0) - margin, 0].max...match.begin(0)].to_s),
           self.class.condense(text[match.end(0), margin].to_s)]
        end

        # Whether some copy of the echo covers [from, to) in `haystack`. Only
        # the last copy starting at or before `from` needs checking: every copy
        # is the same length, so an earlier one ends earlier.
        def covered?(haystack, from, to)
          at = haystack.rindex(condensed, from)
          !at.nil? && (at + condensed.length) >= to
        end

        # Bounded, and searched only until it is found. This runs on the
        # supervisor's only thread every tick, and condensing is linear in the
        # whole accumulated slice: measured at 8ms for 256KB and 124ms for 4MB,
        # so an unbounded version repeated twenty times a second would cost more
        # than the bug it fixes. Once found, the offset is kept and no further
        # scanning happens at all.
        def locate(text)
          return nil if text.bytesize > ECHO_SEARCH_LIMIT || condensed.empty?

          at = self.class.condense(text).index(condensed)
          at && printed_offset(text, at + condensed.length)
        end

        def condensed = @condensed ||= self.class.condense(@text)

        # The index in `text` just past its `count`-th condensed character, or
        # nil. Walks in runs rather than characters so it costs the same order
        # as condensing itself, and consumes exactly what `condense` drops so
        # the two cannot disagree about where a character sits.
        #
        # Counted in characters, like every other offset here.
        # `StringScanner#pos` is a byte offset, and using it would put the
        # boundary mid-character for any prompt carrying an emoji or a curly
        # quote — the same defect the byte/character comment above records.
        def printed_offset(text, count)
          scanner = StringScanner.new(text)
          seen = 0
          index = 0
          until scanner.eos?
            dropped = scanner.scan(ESCAPE_SEQUENCE) || scanner.scan(/\s+/)
            if dropped
              index += dropped.length
              next
            end

            run = scanner.scan(PRINTED)
            if run.nil?
              index += scanner.getch.length
              next
            end
            return index + (count - seen) if (seen + run.length) >= count

            seen += run.length
            index += run.length
          end
          nil
        end
      end
    end
  end
end
