# frozen_string_literal: true

require 'strscan'

module Rune
  module Session
    # One in-flight `send` and the decision of when it has been answered.
    #
    # Extracted from the supervisor because this is where the bugs kept being:
    # four rounds of review found defects here, and each fix had to be reasoned
    # about through an event loop that also owns a pty, a socket, a write queue
    # and a teardown path. Nothing here touches IO — it is given the bytes that
    # have arrived and the facts the loop knows (the clock, whether the child is
    # gone, whether the input has actually been submitted) and returns an
    # outcome or nil for "keep waiting", which makes every rule testable on its
    # own.
    #
    # Everything it holds is bounded and everything it does costs the *new*
    # bytes, not all of them. That is not an optimisation: the supervisor has
    # one thread, so per-tick work proportional to the whole turn is quadratic
    # in the turn, and the profile below is what that cost looks like from
    # outside. See `absorb`.
    #
    # rubocop:disable Metrics/ClassLength -- the echo boundary, the match window and the
    # settle rules are one decision procedure with one piece of state; splitting them across
    # files would put the ordering that makes them correct somewhere no reader passes through,
    # which is the same trade-off supervisor.rb records for the same reason.
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
      # How much output is scanned for an echo before the search is abandoned.
      # A repaint of one line of input costs at most a few tens of KB even when
      # the child redraws on every keystroke; past this the echo is not going to
      # be found and the scan is only costing the event loop.
      ECHO_SEARCH_LIMIT = 256 * 1024
      # How far either side of a candidate match to look for the input being
      # repainted around it, as a multiple of the input's own length. A repaint
      # carries colour and cursor sequences between the characters, so the copy
      # on the wire is several times the text it draws.
      ECHO_COPY_MARGIN = 8
      # ...and a floor under that window, so a one-word input still looks far
      # enough either side to see the copy it sits in.
      REPAINT_MARGIN_FLOOR = 256
      # How much of the child's output one `--wait-for-regex` pattern is matched
      # against: the most recent this many bytes, not the whole turn.
      #
      # This is the deliberate semantic bound, and `docs/sessions.md` documents
      # what it costs a caller. Matching the whole turn is what made a large
      # answer unreachable: every tick re-matched everything that had already
      # arrived, so a 12 MB turn cost O(n^2) and timed out at 90.51s holding 96%
      # of an answer whose marker the child had already printed — while the same
      # turn with no pattern settled in 7.38s.
      MATCH_WINDOW_BYTES = 256 * 1024
      # How far past the window it is allowed to grow before being trimmed back,
      # so trimming costs one copy per this many bytes rather than one per read.
      MATCH_WINDOW_SLACK = 64 * 1024
      # How far back into already-scanned output each tick re-reads. This is the
      # guarantee the bound above is worth stating as: a match up to this many
      # characters long is always found, because on the tick that completes it
      # the scan still starts this far behind where the previous one ended.
      # Longer patterns are the documented limitation.
      MATCH_SPAN = 32 * 1024
      # What `strip` would remove, as a character class, so "has anything
      # actually arrived" can be asked of one chunk without copying it.
      BLANK_CHARACTER = /[^\s\0]/
      # The bytes that continue a UTF-8 character rather than starting one.
      # Trimming the window is a byte operation on text that is valid UTF-8 by
      # construction (the supervisor decodes before it appends), and a cut in
      # the middle of a character would make it neither.
      UTF8_CONTINUATION = (0x80..0xBF)

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
        # Output whose place relative to the echo is not settled yet. Bounded by
        # ECHO_SEARCH_LIMIT, and emptied for good once the boundary is known.
        @pending_echo = +''
        @searched = false
        # ...and the part of it offered to the pattern anyway, once the grace
        # window has closed with nothing found. Provisional: the search goes on,
        # so this can still be withdrawn.
        @provisional = nil
        @located = @echo.empty?
        # The bounded tail of the post-echo output, and how much of it has been
        # offered to the pattern. Characters, like every other offset here.
        @window = +''
        @length = 0
        @scanned = 0
        # The child was still talking when this send landed, so what follows may
        # be the tail of the previous turn rather than a reply to this one.
        @busy_at_send = busy_at_send
      end

      # The text a `--wait-for-regex` pattern is matched against this tick.
      #
      # Once the echo boundary is known, the child's output past it, bounded to
      # the most recent MATCH_WINDOW_BYTES. Before that: nothing while the echo
      # may still be arriving, and everything that has arrived — bounded by
      # ECHO_SEARCH_LIMIT — once the grace window has closed without finding it.
      #
      # Never the caller's reply. `settle_pending` answers with the whole slice,
      # which is unbounded and unchanged by any of this.
      def matchable = @located ? @window : @provisional.to_s

      # Takes the bytes that have arrived since the last call — not the whole
      # slice — and folds them into everything this send needs to decide.
      #
      # Must be called every tick, including with nothing new: the echo grace
      # window expiring is a decision in its own right, and a send whose child
      # has gone silent still has to reach it.
      #
      # Incremental because the alternative was measured and is quadratic. The
      # supervisor reads the pty 4 KB at a time, so a 12 MB turn is ~3000 ticks;
      # re-normalising, re-locating the echo and re-matching the accumulated
      # slice on each of them was 66.69s inside the echo search and 17.65s
      # inside the match, against 7.38s for the same turn with no pattern at all.
      # Worse than slow: the same thread pumps the pty, so the drain starved too
      # and the caller was told it had timed out while holding 11.46 MB of a
      # 12.00 MB answer.
      def absorb(fresh, now:)
        text = fresh.delete("\r")
        @located ? extend_window(text) : sift(text, now: now)
      end

      # The outcome for this tick, or nil to keep waiting.
      def outcome(now:, child_finished:, submitted:, last_output_at:)
        # Nothing that has already arrived can be an answer to input that has
        # not been submitted yet, so while the terminator is still owed only the
        # hard limits apply. Without this a small --settle-ms, or a regex
        # matching a composer repaint, answers the send in the same tick its
        # carriage return goes out — reporting the screen as it was before the
        # child was even given the line.
        return limits(now: now, child_finished: child_finished) unless submitted

        answered(now: now, child_finished: child_finished, last_output_at: last_output_at)
      end

      private

      # Decides where the pty's echo of the input ends, and hands everything
      # past it on.
      #
      # A pty in cooked mode echoes whatever we write straight back, so the
      # first thing to arrive after a send is our own input, not a response.
      # Counting that as "the child started answering" is the difference between
      # working and subtly broken: an agent CLI that echoes the prompt and then
      # thinks for several seconds would settle on the echo alone and hand the
      # caller its own words back.
      def sift(text, now:)
        @pending_echo << text
        ends_at = search_for_echo(text)
        return fix_boundary(@pending_echo[ends_at..].to_s) if ends_at
        # Past what a repaint of one line could possibly occupy with nothing
        # found: this is a child that does not echo at all — ECHO is off, or it
        # is reading raw keystrokes and drawing nothing.
        return fix_boundary(@pending_echo) if @pending_echo.bytesize > ECHO_SEARCH_LIMIT

        # Nothing is offered while the echo might still be arriving. The rule
        # this replaces asked whether the *tail* of the slice was a prefix of
        # the input, which recognises only an echo that is verbatim and
        # unfinished. A child drawing the input into a bordered composer is
        # neither, so a screenful of the caller's own words went to the pattern.
        # Reproduced end to end at 0.19s against a 78-character prompt, decided
        # purely by whether the tick landed before the child's next frame.
        #
        # Past the window it is offered anyway, because withholding further
        # would hang every send to a child that never echoes — measured: a
        # strict version of this rule failed the no-echo case outright. Only
        # provisionally, though, and the search above goes on: a child that
        # echoes a second late is not a child that did not echo, so when its
        # copy of the input does turn up it is recognised, this offer is
        # withdrawn, and the send goes back to waiting for a real answer.
        # Abandoning the search at the grace window instead was measured to
        # settle such a send on the echo alone, 0.8s after it arrived and a
        # second before the child had said anything of its own.
        @provisional = within_echo_grace?(now) ? nil : @pending_echo
      end

      # Only when there is something new to find it in. The search is linear in
      # everything that has arrived, and repeating it against an unchanged
      # buffer twenty times a second is the idle cost this whole change exists
      # to remove.
      def search_for_echo(text)
        return nil if text.empty? && @searched

        @searched = true
        @echo.ends_at(@pending_echo)
      end

      # Once, and for the life of the send: from here on the boundary is a fixed
      # offset and every tick is an append rather than a search.
      def fix_boundary(beyond)
        @located = true
        @provisional = nil
        @pending_echo = +''
        extend_window(beyond)
      end

      # Records that something other than the pty's echo has arrived. Settling
      # additionally requires this: "never started" is a timeout, not a settle,
      # and callers who genuinely expect no reply use --no-wait.
      #
      # Latched, because a send that has seen output cannot unsee it — and
      # because asking the question of one chunk rather than of everything so
      # far is the whole point of doing this incrementally.
      def extend_window(text)
        return if text.empty?

        @saw_output ||= text.match?(BLANK_CHARACTER)
        @window << text
        @length += text.length
        trim_window
      end

      # Drops the front of the window once it has outgrown its bound, keeping at
      # least MATCH_WINDOW_BYTES so the guarantee `MATCH_SPAN` states still
      # holds. Trimmed in slack-sized steps rather than on every read, because
      # each trim copies what it keeps.
      def trim_window
        return if @window.bytesize <= MATCH_WINDOW_BYTES + MATCH_WINDOW_SLACK

        cut = character_start(@window.bytesize - MATCH_WINDOW_BYTES)
        dropped = @window.byteslice(0, cut).length
        @window = @window.byteslice(cut..).to_s
        @length -= dropped
        @scanned = [@scanned - dropped, 0].max
      end

      def character_start(at)
        at += 1 while at < @window.bytesize && UTF8_CONTINUATION.cover?(@window.getbyte(at))
        at
      end

      def limits(now:, child_finished:)
        return { settled: false, timed_out: true } if now >= @deadline
        return { settled: true, child_exited: true } if child_finished

        nil
      end

      # Ordered by precedence: an explicit regex match beats the clock, the hard
      # cap beats a settle that has not happened yet, and a child that exited
      # ends the wait whatever the settle window says.
      def answered(now:, child_finished:, last_output_at:)
        matched = regex_matched?
        return { settled: false, regex_timed_out: true } if matched.nil?
        return { settled: true, matched: true } if matched
        return { settled: false, timed_out: true } if now >= @deadline
        return { settled: true, child_exited: true } if child_finished
        # Quiet does not answer a send that is waiting for a pattern. It used
        # to, so `--wait-for-regex DONE --settle-ms 800` returned `settled:
        # true, matched: nil` at 800ms on a child that prints DONE five seconds
        # later — 3/3 — and the documented workaround for the settle bug did not
        # work at the default settle window. A regex send now answers on a
        # match, on the child exiting, or on `--timeout-ms`, and reports
        # `matched:` either way so the caller can tell the difference.
        return nil if @regex
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
      #
      # Resumed rather than restarted. `\A` is why this passes a position to
      # `Regexp#match` instead of matching a substring: an anchored pattern must
      # not be satisfied by wherever this tick's scan happens to begin, and Ruby
      # refuses `\A` at any position past zero, which is exactly the rule wanted
      # here. Everything before `MATCH_SPAN` characters back has been scanned
      # already, at a tick where it was equally complete.
      def regex_matched?
        return false unless @regex

        text = matchable
        first = @regex.match(text, scan_start)
        return false unless first
        return true unless @echo.repaint?(text, first)

        last = last_match(text, first)
        !last.nil? && !@echo.repaint?(text, last)
      rescue REGEX_TIMEOUT_ERROR
        nil
      end

      # Where this tick's scan begins, and the only place the resumption point
      # moves. Zero while the echo boundary is still open: what is offered then
      # is provisional and bounded by ECHO_SEARCH_LIMIT, so re-reading all of it
      # costs a fixed amount and remembering a position in it would be wrong.
      def scan_start
        return 0 unless @located

        from = [@scanned - MATCH_SPAN, 0].max
        @scanned = @length
        from
      end

      # The last place the pattern matches, when the earliest one turned out to
      # be a copy of the input.
      #
      # Two candidates, because they answer different failure modes. A
      # line-oriented child says its answer once and the earliest match is it. A
      # full-screen child redraws the whole frame — input included — many times
      # a second, so the frames after the located echo contain the input again
      # and the earliest match is a repaint; the answer, when it comes, is at
      # the end. Taking only one of the two loses one of those cases, and taking
      # every match would mean one MatchData and one repaint test per repaint
      # per tick, which is unbounded work for a pattern like `.`.
      #
      # A reverse scan of the whole window is the expensive half (1.27ms per
      # 512KB against 0.09ms forward), so it runs only when there is something
      # to reject: the common case, no match yet, costs one forward scan of what
      # is new.
      def last_match(text, first)
        at = text.rindex(@regex)
        return nil if at.nil? || at <= first.begin(0)

        @regex.match(text, at)
      end

      def within_echo_grace?(now) = (now - @sent_at) < ECHO_GRACE_SECONDS

      def quiet_enough?(now:, last_output_at:)
        return false unless @saw_output || provisional_output?
        return false if last_output_at.nil?

        (now - last_output_at) >= (@settle_ms / 1000.0)
      end

      # Output offered before the echo boundary was fixed counts, but is not
      # latched: it is exactly the text a late-arriving echo would take back,
      # and a send must not settle on words it has since learnt were its own.
      # Stops at the first printing character, so this costs the leading
      # whitespace and no more.
      def provisional_output? = !@provisional.nil? && @provisional.match?(BLANK_CHARACTER)

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
          @condensed = nil
        end

        def empty? = @text.empty?

        # The character offset just past the echo, or nil while no copy of the
        # input has been found in what has arrived.
        def ends_at(arrived)
          # Located, not prefix-matched. The cursor is taken the instant we
          # write, so bytes the child was already emitting (the tail of its
          # previous prompt, a redraw) can land *before* the echo — which made a
          # prefix check fail and hand the whole slice back as if it were a
          # reply.
          verbatim = arrived.index(@text)
          return verbatim + @text.length if verbatim

          # Verbatim is the exception, not the rule. A child that *transforms*
          # the echo produces no such substring at all: python's REPL redraws
          # the line in colour on every keystroke, and readline splits the echo
          # with a space and a carriage return where it wraps the terminal
          # (measured at 120 columns: 110 characters echo as one run, 111 do
          # not). Neither is exotic, both defeated the check above, and the
          # whole slice — echo included — was then handed to the pattern, which
          # answered `matched` before the child had run a line of the input.
          locate(arrived)
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

        # Bounded, and only ever asked of output the echo could still be in.
        # Condensing is linear in what it is given — measured at 8ms for 256KB
        # and 124ms for 4MB — so the caller stops asking once what has arrived
        # outgrows ECHO_SEARCH_LIMIT rather than paying that on every read for
        # the rest of the turn.
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
    # rubocop:enable Metrics/ClassLength
  end
end
