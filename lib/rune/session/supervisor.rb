# frozen_string_literal: true

require 'json'
require 'socket'
require 'fileutils'
require 'io/wait'
require 'shellwords'
require_relative 'store'
require_relative 'prompt_scanner'
require_relative '../utf8_stream_decoder'

# IO#winsize= comes from this stdlib extension. Rescued on LoadError the same
# way pty_runner.rb rescues 'pty' and pty_watcher.rb rescues 'io/console':
# expected almost everywhere, guaranteed nowhere.
begin
  require 'io/console'
rescue LoadError
  nil
end

# Required here so this file is loadable on its own rather than relying on some
# other file having pulled `pty` in first — but rescued, because rune as a whole
# must still *load* on a Ruby built without the optional pty extension. A bare
# `require` here broke exactly that, which the non-PTY portability spec caught.
begin
  require 'pty'
rescue LoadError
  nil
end

module Rune
  module Session
    # The detached process that owns one session's PTY master for the whole
    # life of that session, and serves its control socket.
    #
    # Single-threaded on purpose. A `send` has to keep draining the PTY while
    # it waits for the child to go quiet, so the naive "block in the client
    # handler" shape deadlocks: nothing would be reading the pty, the child
    # would fill its buffer and stall, and the settle window would never
    # elapse because no output ever arrived. One `IO.select` loop that pumps
    # the pty and resolves at most one pending send per tick avoids that
    # without threads or locks.
    #
    # rubocop:disable Metrics/ClassLength -- the pty lifecycle, control protocol, and settle
    # state machine are kept together so every path that can strand a child process stays
    # auditable in one place, matching pty_watcher.rb's rationale for the same trade-off.
    class Supervisor
      POLL_INTERVAL = 0.05
      READ_CHUNK = 4096
      # Same pager neutralization PTYWatcher applies: an interactive pager in a
      # driven session waits for a keypress nobody will ever send.
      CHILD_ENV = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }.freeze
      DEFAULT_ROWS = 40
      DEFAULT_COLUMNS = 120
      # How long after a send a prefix-of-the-input may still be assumed to be
      # the pty's own echo. A cooked-mode echo is produced by the kernel line
      # discipline as we write, so it lands in single-digit milliseconds; this
      # is deliberately generous against load.
      ECHO_GRACE_SECONDS = 0.5
      # How much of the existing transcript an attaching terminal is replayed,
      # so it lands on a populated screen rather than a blank one.
      ATTACH_BACKLOG_BYTES = 64 * 1024
      # Bounds on reading one control request, so a client that stalls mid-line
      # or floods cannot hold or exhaust the supervisor.
      REQUEST_READ_TIMEOUT = 2.0
      MAX_REQUEST_BYTES = 1024 * 1024
      # Per-terminal ceiling on undrained output before that terminal is dropped.
      MAX_OUTBOX_BYTES = 4 * 1024 * 1024
      # How long teardown will keep trying to push out replies that are already
      # queued. Bounded so a caller that stopped reading cannot hold the
      # supervisor open, but long enough to finish a reply larger than one
      # socket buffer.
      REPLY_DRAIN_TIMEOUT = 2.0
      # How long the child must be quiet before a send is considered answered.
      #
      # 0.4.0 raised this to 3000 on a measurement that was wrong twice over. Both
      # harnesses reproduced bugs they were meant to be independent of: prompts
      # over ~64 characters were never submitted to Claude Code at all, and grok's
      # answers were scored missing because the probe searched the byte stream
      # where repaints had split them. Re-measured with both fixed, on the
      # rendered screen, the reply was the answer to the question actually asked
      # in 27/27 claude turns and 18/18 grok turns — at every window including
      # 800 ms. The larger window bought nothing and cost up to double the
      # latency per call (grok 8.7s to 16.8s), so this returns to 800.
      #
      # What the evidence does not cover: two agents and 45 turns, both driving
      # TUIs whose spinner runs for the whole turn, which is what makes byte
      # silence mean "finished". A callee that goes quiet mid-turn for longer
      # than this still truncates, and `--settle-ms` is the knob for it.
      DEFAULT_SETTLE_MS = 800
      # How long after writing a send's text the terminating carriage return
      # is written, as its own write. Long enough that the child completes a read
      # in between, short enough to be invisible next to a model round trip.
      SUBMIT_DELAY = 0.05
      # How long one `--wait-for-regex` match may run. Generous for any sane
      # pattern against a screenful of output, and short enough that a
      # pathological one costs a fraction of a tick rather than the session.
      REGEX_MATCH_TIMEOUT = 0.25
      # Ruby 3.0 and 3.1 have no Regexp::TimeoutError; a class that is never
      # raised keeps the rescue clause valid there without widening it.
      REGEX_TIMEOUT_ERROR = defined?(Regexp::TimeoutError) ? Regexp::TimeoutError : Class.new(StandardError)
      # Recorded as the session's exit code when the supervisor itself died
      # rather than the child. 70 is sysexits' EX_SOFTWARE: an internal fault,
      # distinct from any status the child could have returned.
      EXIT_SUPERVISOR_CRASHED = 70

      def self.run(name:, command:, home: nil, project: nil)
        new(name: name, command: command, store: Store.new(home: home, project: project)).run
      end

      def initialize(name:, command:, store:)
        @name = name
        @command = Array(command).map(&:to_s)
        @store = store
        @transcript = +''
        @decoder = UTF8StreamDecoder.new
        @pending = nil
        @clients = []
        @attached = []
        # Anything we could not hand off immediately, keyed by the IO it is
        # destined for. The event loop drains these when the IO reports
        # writable, so a child or terminal that stops reading costs memory and
        # eventually its own connection — never the whole session.
        @outbox = Hash.new { |queue, io| queue[io] = +'' }
        @accepted_at = {}
        @close_after_drain = []
        @stopping = false
        @submit_at = nil
        @exit_code = nil
        @finished = false
      end

      def run
        detach_from_terminal
        @output_log = @store.open_output(@name)
        server = build_server
        reader, writer, pid = PTY.spawn(CHILD_ENV, *@command)
        @child_pid = pid
        @writer = writer
        apply_window_size(writer)
        record_running(pid)
        log_event('start', command: Shellwords.join(@command), pid: pid)
        event_loop(server, reader, writer)
      rescue Errno::ENOENT, Errno::EACCES => e
        # Same convention PTYRunner/PTYWatcher use: a missing (127) or
        # non-executable (126) target is the child's exit status, not a
        # supervisor-level crash.
        finish(e.is_a?(Errno::ENOENT) ? 127 : 126)
      rescue StandardError => e
        crashed(e)
      ensure
        cleanup(server)
      end

      private

      # Without setsid the supervisor stays in the launching shell's session
      # and dies with it (SIGHUP on terminal close), which would defeat the
      # entire point of a persistent session. Rescued because it legitimately
      # fails when the process is already a session leader.
      def detach_from_terminal
        Process.setsid
      rescue Errno::EPERM, NotImplementedError
        nil
      end

      def build_server
        path = @store.socket_path(@name)
        # Only remove a socket nobody is answering on. `running_conflict` guards
        # this at the CLI layer, but two concurrent starts race it, and blindly
        # unlinking would leave the first supervisor serving an unlinked fd
        # while every new client reached the second — two supervisors disagreeing
        # about one session's transcript and cursors.
        raise "session #{@name} is already being served" if socket_live?(path)

        FileUtils.rm_f(path)
        server = Store.with_bindable_path(path) { |bindable| UNIXServer.new(bindable) }
        File.chmod(Store::FILE_MODE, path)
        server
      end

      def socket_live?(path)
        return false unless File.socket?(path)

        Store.with_bindable_path(path) { |bindable| UNIXSocket.new(bindable) }.close
        true
      rescue SystemCallError
        false
      end

      # A detached session has no controlling terminal to copy dimensions from,
      # and an unset pty defaults to 0x0. Most agent CLIs are full-screen TUIs
      # that lay out against those dimensions, so leaving them unset gives a
      # child that renders into nothing — found immediately when driving a real
      # agent, whose entire first output was terminal setup and no UI.
      # PTYWatcher copies the human's real size; here a sane fixed default is
      # the closest equivalent.
      def apply_window_size(writer)
        writer.winsize = [DEFAULT_ROWS, DEFAULT_COLUMNS]
      rescue IOError, SystemCallError, NoMethodError
        nil
      end

      def record_running(pid)
        @store.update_meta(@name, state: 'running', child_pid: pid, supervisor_pid: Process.pid)
      end

      def event_loop(server, reader, writer)
        until @stopping
          ready = IO.select([server, reader, *@clients, *@attached, *pending_client],
                            @outbox.keys, nil, POLL_INTERVAL)
          if ready
            dispatch_ready(ready, server, reader, writer)
            drain_outbox(ready[1])
          end
          deliver_submit
          resolve_pending
          reap_idle_clients
          break if @child_finished && @pending.nil?
        end
        conclude
      end

      # Kill before reaping on the stop path. `reap` is a bare Process.wait2, so
      # on an explicit stop of a long-lived agent it blocked forever: the
      # supervisor never reached `finish` or `cleanup`, leaving meta stale and
      # any in-flight send unanswered. It only looked fine from the CLI because
      # `rune session stop` SIGKILLs afterwards.
      def conclude
        terminate_child if @stopping && !@child_finished
        finish(@exit_code || reap)
      end

      def dispatch_ready(ready, server, reader, writer)
        ready[0].each do |io|
          if io.equal?(server)
            accept_client(server)
          elsif io.equal?(reader)
            pump(reader)
          elsif pending_client.include?(io)
            discard_disconnected_pending(io)
          elsif @attached.include?(io)
            forward_from_attached(io, writer)
          else
            @clients.delete(io)
            @accepted_at.delete(io)
            handle_request(io, writer)
          end
        end
      end

      # The in-flight send's socket is watched too. A caller that is killed or
      # cancelled mid-send leaves it readable at EOF; without noticing, the
      # supervisor holds @pending for the whole --timeout-ms and refuses every
      # later send with "a send is already in flight" — so one cancelled call
      # locks the session for two minutes at the default timeout.
      def pending_client = @pending ? [@pending[:client]] : []

      def discard_disconnected_pending(client)
        return unless client_gone?(client)

        @pending = nil
        safe_close(client)
      end

      # `eof?` would block on a live socket, but this is only reached once
      # IO.select reported the socket readable, so it returns immediately:
      # true at EOF, false when the peer actually sent something.
      def client_gone?(client)
        client.eof?
      rescue IOError, SystemCallError
        true
      end

      # Queue rather than write. `write` on a pty master or a socket blocks once
      # the peer stops draining it, and this is the only thread — blocking here
      # stops pty pumping, settle evaluation, and stop handling all at once,
      # which is how a large prompt to a child that was not reading stdin could
      # wedge an entire session with no recovery but killing it.
      def enqueue(io, bytes)
        return if bytes.nil? || bytes.empty?

        @outbox[io] << bytes
        # An attached terminal that never drains would otherwise grow its queue
        # without limit until the supervisor runs out of memory. The spec always
        # claimed such a peer "eventually" loses its connection; this is what
        # makes that true.
        #
        # Attached terminals only. Capping every non-master IO also capped
        # control replies, and `settle_pending` answers with the whole captured
        # slice: one long turn from a TUI agent (megabytes of redraws, inflated
        # again by JSON escaping) crossed the ceiling and the reply was dropped
        # unwritten. The caller saw "not reachable" for a send that had in fact
        # completed, and retried a turn the child had already done.
        return drop_writer(io) if @attached.include?(io) && @outbox[io].bytesize > MAX_OUTBOX_BYTES

        flush_outbox(io)
      end

      def drain_outbox(writable)
        Array(writable).each { |io| flush_outbox(io) }
      end

      def flush_outbox(io)
        pending = @outbox[io]
        return @outbox.delete(io) if pending.empty?

        written = io.write_nonblock(pending, exception: false)
        if written == :wait_writable
          nil
        elsif written >= pending.bytesize
          @outbox.delete(io)
          # A reply is only closed once it has actually gone out; closing at
          # write time would truncate anything the socket could not take yet.
          safe_close(io) if @close_after_drain.include?(io)
        else
          @outbox[io] = pending.byteslice(written..).to_s
        end
      rescue IOError, SystemCallError
        drop_writer(io)
      end

      # A terminal that has gone away (or stopped reading for good) loses its
      # attachment; the pty master failing means the child is gone.
      #
      # This compares against the stored master rather than a parameter threaded
      # through every caller: `enqueue` called `flush_outbox` without one, so a
      # failed write to the pty was mistaken for a dead terminal — closing the
      # master and leaving `@child_finished` false, which left the in-flight
      # send waiting out its whole timeout instead of reporting the exit.
      def drop_writer(io)
        return @child_finished = true if @writer && io.equal?(@writer)

        detach(io)
      end

      # Back to the headless default when the last terminal goes, so a session's
      # geometry does not depend on whether a human happened to attach earlier —
      # programmatic sends should render the same either way.
      def detach(client)
        @attached.delete(client)
        safe_close(client)
        resize_child(@writer, DEFAULT_ROWS, DEFAULT_COLUMNS) if @attached.empty? && @writer
      end

      def accept_client(server)
        client = server.accept_nonblock
        @clients << client
        @accepted_at[client] = monotonic
      rescue IO::WaitReadable, Errno::ECONNABORTED
        nil
      end

      # A peer that connects and then says nothing is never readable, so it was
      # never examined and stayed in the client set for the life of the session.
      # Enough of those exhaust the supervisor's file descriptors, after which
      # it can neither accept nor pump and the session is stuck. A client that
      # has sent something is already out of this set by the time it is handled,
      # so only genuinely silent connections are reaped.
      def reap_idle_clients
        cutoff = monotonic - REQUEST_READ_TIMEOUT
        @clients.dup.each do |client|
          next if (@accepted_at[client] || cutoff) > cutoff

          @clients.delete(client)
          @accepted_at.delete(client)
          safe_close(client)
        end
      end

      def pump(reader)
        append(@decoder.decode(reader.readpartial(READ_CHUNK)))
      rescue Errno::EIO, EOFError, PTY::ChildExited
        append(@decoder.finish)
        @child_finished = true
      end

      def append(text)
        return if text.nil? || text.empty?

        @transcript << text
        @last_output_at = monotonic
        log_event('output', bytes: text.bytesize, text: text)
        broadcast(text)
      end

      # ---- attach: a human terminal taking over a live session

      # Everything the child prints also goes to every attached terminal, so an
      # attached human sees the session live. A terminal that has gone away is
      # dropped rather than allowed to break the loop.
      def broadcast(text)
        @attached.dup.each { |client| enqueue(client, text) }
      end

      # After the ack line the socket stops being a request/reply channel and
      # becomes a raw duplex pipe to the pty, which is what lets a human type
      # into a session an agent started.
      def handle_attach(client, request, writer)
        # Queued, not written: `puts`/`flush` here were the last blocking writes
        # left on the event-loop thread. The outbox is one ordered buffer per
        # peer, so the ack still precedes the backlog replay below.
        enqueue(client, "#{JSON.generate(attached: true, cursor: @transcript.bytesize)}\n")
        # The attaching terminal's real dimensions, so a full-screen agent
        # started headless at the default size reflows to the human's window
        # instead of rendering 40x120 inside it.
        resize_child(writer, request[:rows], request[:cols])
        # Registered last: an exception after this point used to leave a closed
        # socket in @attached, which the next IO.select then raised on.
        @attached << client
        enqueue(client, recent_transcript)
      rescue IOError, SystemCallError
        safe_close(client)
      end

      # Sent over its own short-lived control connection rather than inline,
      # because after the attach ack the attachment socket is a raw byte pipe
      # to the pty — a control frame in that stream would be typed at the child.
      def handle_resize(request, client, writer)
        resize_child(writer, request[:rows], request[:cols])
        respond(client, resized: true)
      end

      def resize_child(writer, rows, cols)
        rows = Integer(rows)
        cols = Integer(cols)
        return unless rows.positive? && cols.positive?

        writer.winsize = [rows, cols]
        # SIGWINCH is what tells a TUI to re-lay-out; setting the size alone
        # leaves it drawing at the old geometry until something else repaints.
        # Skipped once the child is known gone: the pid may since belong to
        # something else entirely.
        Process.kill('WINCH', @child_pid) if @child_pid && !@child_finished
      rescue TypeError, ArgumentError, IOError, SystemCallError, NoMethodError
        nil
      end

      # Replayed on attach so the terminal shows the session's current screen
      # instead of an empty one until the child happens to repaint.
      def recent_transcript
        @transcript.byteslice([@transcript.bytesize - ATTACH_BACKLOG_BYTES, 0].max..).to_s.scrub
      end

      def forward_from_attached(client, writer)
        enqueue(writer, client.read_nonblock(READ_CHUNK))
      rescue IO::WaitReadable
        nil
      rescue IOError, SystemCallError
        detach(client)
      end

      # ---- control protocol: one JSON request line in, one JSON reply line out

      def handle_request(client, writer)
        line = read_request_line(client)
        return safe_close(client) if line.nil?

        request = JSON.parse(line, symbolize_names: true)
        dispatch(request, client, writer)
      rescue JSON::ParserError
        respond(client, error: 'malformed request')
      # SystemCallError covers ECONNRESET and friends: a control client that is
      # killed mid-line used to unwind the event loop, and `run`'s ensure then
      # ran cleanup, which SIGKILLed a perfectly healthy child. A broken client
      # must never be able to take the session down with it.
      rescue IOError, SystemCallError
        safe_close(client)
      end

      # `gets` blocks until a newline arrives, so a client that connects and
      # sends half a line would freeze the supervisor's only thread — stopping
      # pty pumping (which stalls the child once its buffer fills) and every
      # pending settle along with it. Bounded instead, so a broken or hostile
      # client costs one short wait and its own connection, never the session.
      def read_request_line(client)
        deadline = monotonic + REQUEST_READ_TIMEOUT
        buffer = +''
        loop do
          chunk = client.read_nonblock(READ_CHUNK, exception: false)
          return nil if chunk.nil? || buffer.bytesize > MAX_REQUEST_BYTES

          if chunk == :wait_readable
            return nil unless monotonic < deadline && client.wait_readable(0.05)
          else
            buffer << chunk
            return buffer if buffer.include?("\n")
          end
        end
      end

      def dispatch(request, client, writer)
        case request[:op]
        when 'send' then handle_send(request, client, writer)
        when 'status' then respond(client, status_payload)
        when 'attach' then handle_attach(client, request, writer)
        when 'resize' then handle_resize(request, client, writer)
        when 'stop' then handle_stop(client)
        else respond(client, error: "unknown op: #{request[:op]}")
        end
      end

      def handle_send(request, client, writer)
        return respond(client, error: 'a send is already in flight on this session') if @pending
        return respond(client, error: 'session child has exited') if @child_finished

        begin
          echo = write_to_child(writer, request)
        rescue Errno::EIO, Errno::EPIPE, IOError
          # The child died between `pump` last running and this write, so
          # @child_finished was still false when we checked it above. Without
          # this the exception unwound the whole event loop: `finish` was
          # skipped so meta stayed "running", and the caller saw a dropped
          # connection instead of a clear answer.
          @child_finished = true
          return respond(client, error: 'session child has exited')
        end
        # The queued write can fail without raising here: `enqueue` reports a
        # dead master by setting @child_finished, it does not propagate. A
        # waiting send is caught later the same tick by `resolve_pending`, but
        # --no-wait has no such check, so it answered `sent: true` for bytes
        # that reached nothing.
        return respond(client, error: 'session child has exited') if @child_finished
        return respond(client, sent: true, waited: false) if request[:no_wait]

        begin_pending(request, client, echo)
      end

      # Enter is carriage return, not line feed. A real terminal sends \r when
      # you press Enter, so raw-mode TUIs — which is most agent CLIs — listen
      # for \r and ignore \n: the text lands in their input box and simply
      # never submits. Cooked-mode children are unaffected because the line
      # discipline translates \r to \n on input (ICRNL), so \r is the terminator
      # that works for both. Found by driving a real agent, whose prompt sat
      # unsent in its composer while rune reported a clean settle.
      # The terminator is a *separate* write, deliberately delayed.
      #
      # Agent TUIs treat a large chunk arriving in one read as a paste, and a
      # carriage return inside a paste is a newline in the composer rather than
      # Enter. Writing text and terminator together therefore typed the prompt
      # and never sent it: measured against Claude Code, every input of about 64
      # characters or more sat unsubmitted while rune reported a clean settle —
      # and an agent prompt is almost always longer than that. Splitting the
      # write fixes it (verified 61 chars submitted, 82 did not; separate write
      # submitted, as did writing the text in small pieces).
      def write_to_child(writer, request)
        # Ordering beats delay if two sends are in flight: an outstanding
        # terminator goes out now rather than after this text.
        flush_submit
        text = request[:text].to_s
        enqueue(writer, text)
        schedule_submit unless request[:no_newline]
        text
      end

      def schedule_submit = @submit_at = monotonic + SUBMIT_DELAY

      # Once the delay has passed *and* the text has fully drained, so the child
      # cannot receive both in a single read.
      def deliver_submit
        return if @submit_at.nil? || monotonic < @submit_at
        return if @writer.nil? || @child_finished
        return if @outbox.key?(@writer) && !@outbox[@writer].empty?

        flush_submit
      end

      def flush_submit
        return if @submit_at.nil?

        @submit_at = nil
        enqueue(@writer, "\r") if @writer && !@child_finished
      end

      # The cursor is taken here, before waiting, so the reply contains only
      # what this send produced. Without it a banner or a previous command's
      # trailing output would be misattributed to this request.
      def begin_pending(request, client, echo)
        settle_ms = positive_int(request[:settle_ms], DEFAULT_SETTLE_MS)
        timeout_ms = positive_int(request[:timeout_ms], 120_000)
        @pending = {
          client: client,
          cursor: @transcript.bytesize,
          settle_ms: settle_ms,
          regex: compile_regex(request[:wait_for_regex]),
          deadline: monotonic + (timeout_ms / 1000.0),
          echo: echo,
          # The child was still talking when this send landed, so what follows
          # may be the tail of the previous turn rather than a reply to this
          # one. Measured against a real agent CLI, that is the characteristic
          # failure: not a truncated answer but the previous answer, whole and
          # well-formed, which a caller cannot tell from a correct one. It is
          # reported rather than prevented — waiting for quiet before writing
          # would need another deferred state in this loop.
          busy_at_send: child_still_talking?(settle_ms),
          sent_at: monotonic,
          saw_output: false
        }
      end

      # Bounded, because the match runs on the only thread. A pattern that
      # backtracks catastrophically blocks inside `match?`, which means the loop
      # cannot pump the pty, cannot answer `stop`, and — the part that makes it
      # worse than slow — cannot even check the send's own `--timeout-ms`.
      # Reproduced with `--wait-for-regex='(a+)+\1$'` against 60 a's: the send
      # was still blocked long after its 8s deadline. Ruby memoizes most
      # textbook cases since 3.2, but that optimization is off for patterns
      # using backreferences, which is exactly the shape that got through.
      def compile_regex(source)
        return nil if source.nil? || source.empty?
        return Regexp.new(source) unless supports_regex_timeout?

        Regexp.new(source, timeout: REGEX_MATCH_TIMEOUT)
      rescue RegexpError
        nil
      end

      # Ruby 3.2 added per-Regexp timeouts, and `Regexp#timeout` with them. rune
      # still supports 3.0, where the only defence is the documented limitation
      # — and where passing an unknown keyword would be silently taken as the
      # options argument rather than rejected, so this is a capability check
      # rather than a rescue.
      def supports_regex_timeout? = Regexp.method_defined?(:timeout)

      def resolve_pending
        return unless @pending

        slice = @transcript.byteslice(@pending[:cursor]..) || ''
        @pending[:saw_output] = true unless beyond_echo(slice).strip.empty?
        outcome = pending_outcome(slice)
        settle_pending(slice, **outcome) if outcome
      end

      # Ordered by precedence: an explicit regex match beats the clock, the
      # hard cap beats a settle that has not happened yet, and a child that
      # exited ends the wait whatever the settle window says.
      def pending_outcome(slice)
        # Against the post-echo text, not the raw slice. Matching the raw slice
        # meant `--wait-for-regex MARKER` on `echo MARKER` returned the instant
        # the pty echoed the command back — handing the caller its own words as
        # the "answer" before the child had produced any. Waiting for a marker
        # you just asked an agent to print is the normal case, so the documented
        # deterministic escape hatch was the least reliable path in practice.
        matched = regex_matched?(slice)
        return { settled: false, regex_timed_out: true } if matched.nil?
        return { settled: true, matched: true } if matched
        return { settled: false, timed_out: true } if monotonic >= @pending[:deadline]
        return { settled: true, child_exited: true } if @child_finished
        return { settled: true } if quiet_enough?

        nil
      end

      # True on a match, false on none, nil when the pattern exceeded its match
      # budget. Giving up on the pattern is the only sane answer: retrying it
      # next tick would spend the budget again on a slice that only grows, so
      # the send would burn the loop until its deadline instead of answering.
      def regex_matched?(slice)
        regex = @pending[:regex]
        return false unless regex

        regex.match?(beyond_echo(slice))
      rescue REGEX_TIMEOUT_ERROR
        nil
      end

      # A pty in cooked mode echoes whatever we write straight back, so the
      # first thing to arrive after a send is our own input, not a response.
      # Counting that as "the child started answering" is the difference
      # between working and subtly broken: an agent CLI that echoes the prompt
      # and then thinks for several seconds would settle on the echo alone and
      # return the caller its own words back. Only output beyond the echo
      # starts the settle clock.
      #
      # Compared with \r removed because the terminal rewrites \n as \r\n. The
      # echo is still included in the returned output — dropping data silently
      # would be worse than a little noise the caller can see and slice off.
      def beyond_echo(slice)
        normalized = slice.delete("\r")
        echo = @pending[:echo].to_s.delete("\r")
        return normalized if echo.empty?

        # Located, not prefix-matched. The cursor is taken the instant we write,
        # so bytes the child was already emitting (the tail of its previous
        # prompt, a redraw) can land *before* the echo — which made a prefix
        # check fail and hand the whole slice back as if it were a reply. That
        # showed up as --wait-for-regex matching its own echoed input roughly
        # one run in three.
        # Characters throughout. `index` and `[]` count characters, so advancing
        # past the echo by its *byte* length overshot for any non-ASCII input —
        # a prompt containing a curly quote or an emoji silently ate the first
        # bytes of the reply.
        index = normalized.index(echo)
        return normalized[(index + echo.length)..].to_s if index
        # Not all there yet: treat a trailing partial echo as "still arriving",
        # but only inside the grace window, so a genuine reply that happens to
        # be a prefix of the input cannot stall the send indefinitely.
        return '' if within_echo_grace? && echo_still_arriving?(normalized, echo)

        normalized
      end

      # True when the tail of what has arrived is the beginning of the echo,
      # i.e. the echo is mid-flight. Comparing the *whole* slice was wrong: a
      # child that was still printing something else (bash's startup banner)
      # when the send landed pushes the partial echo off the front, so the
      # prefix test failed and a half-arrived echo counted as a reply.
      # Characters, not bytes. `normalized[-length, length]` counts characters
      # while the bound was counted in bytes, so any multibyte output inside the
      # echo grace window — a spinner glyph, a box-drawing rule, which is most
      # of what an agent TUI paints — asked for more characters than existed and
      # got nil, and `start_with?(nil)` raised. That killed the whole supervisor
      # and took the agent CLI with it, reproducibly, within a handful of turns.
      def echo_still_arriving?(normalized, echo)
        return true if normalized.strip.empty?

        limit = [normalized.length, echo.length].min
        (1..limit).any? { |length| echo.start_with?(normalized[-length, length]) }
      end

      def within_echo_grace?
        (monotonic - @pending[:sent_at]) < ECHO_GRACE_SECONDS
      end

      # Settling additionally requires at least one chunk of non-echo output.
      # "Never started" is a timeout, not a settle; callers who genuinely
      # expect no reply use --no-wait.
      def quiet_enough?
        return false unless @pending[:saw_output]
        return false if @last_output_at.nil?

        (monotonic - @last_output_at) >= (@pending[:settle_ms] / 1000.0)
      end

      # True when the child produced output within the settle window that is
      # about to be applied — i.e. a previous turn had not finished when this
      # send arrived.
      def child_still_talking?(settle_ms)
        return false if @last_output_at.nil?

        (monotonic - @last_output_at) < (settle_ms / 1000.0)
      end

      def settle_pending(slice, **flags)
        pending = @pending
        @pending = nil
        respond(pending[:client], {
          output: slice,
          cursor: @transcript.bytesize,
          prompt_detected: PromptScanner.prompt_at_end?(slice),
          busy_at_send: pending[:busy_at_send] || false
        }.merge(flags))
      end

      def handle_stop(client)
        respond(client, stopping: true)
        @stopping = true
      end

      def status_payload
        {
          name: @name,
          state: @child_finished ? 'exited' : 'running',
          child_pid: @child_pid,
          supervisor_pid: Process.pid,
          cursor: @transcript.bytesize
        }
      end

      # Queued like everything else, then closed once it has drained. `puts` +
      # `flush` here were the last blocking writes on this thread: a control
      # peer that sent a request and then stopped reading its reply could stall
      # the loop, which made invariant "nothing blocks on a write" untrue for
      # the one path most likely to face a misbehaving client.
      def respond(client, payload)
        @close_after_drain << client
        enqueue(client, "#{JSON.generate(payload)}\n")
      end

      # ---- teardown

      def finish(exit_code)
        @finished = true
        @exit_code = exit_code
        @store.update_meta(@name, state: 'exited', exit_code: exit_code, exited_at: Time.now.to_f)
        log_event('exit', exit_code: exit_code)
      end

      # A supervisor that dies without saying why is undebuggable. Driving a
      # real agent CLI produced exactly that: the socket was gone, the caller
      # got `supervisor_exited`, and `meta.json` still read "running" with no
      # exit code and an empty supervisor.log — nothing anywhere named the
      # cause. The transcript is where an operator already looks, so the cause
      # goes there as well as on stderr.
      def crashed(error)
        log_event('crash', error: error.class.name, message: error.message,
                           backtrace: Array(error.backtrace).first(10))
        warn "rune session #{@name}: supervisor crashed: #{error.class}: #{error.message}"
        warn Array(error.backtrace).first(10).join("\n")
        finish(EXIT_SUPERVISOR_CRASHED)
      end

      def reap
        return nil unless @child_pid

        _, status = Process.wait2(@child_pid)
        status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
      rescue Errno::ECHILD
        0
      end

      # Each step is isolated: teardown previously shared one rescue, so a child
      # that would not die took the socket removal and the file descriptors down
      # with it, leaving a stale control socket that later clients connect to and
      # get ECONNREFUSED from instead of a clean "not running" result.
      def cleanup(server)
        [
          -> { resolve_orphaned_pending },
          -> { drain_replies },
          # Whatever brought us here, the session is over. Leaving meta saying
          # "running" makes every later command report a session that is not
          # there, with no exit code to explain it — and `list` then shows a
          # live session backed by nothing.
          -> { finish(EXIT_SUPERVISOR_CRASHED) unless @finished },
          -> { terminate_child },
          -> { (@clients + @attached).each { |client| safe_close(client) } },
          -> { safe_close(server) },
          -> { FileUtils.rm_f(@store.socket_path(@name)) },
          -> { @output_log&.close }
        ].each do |step|
          step.call
        rescue StandardError
          next
        end
      end

      # Queueing a reply is not delivering it. `write_nonblock` takes at most one
      # socket buffer (~8 KiB on macOS), so settling a large slice leaves the
      # rest in @outbox — and the event loop exits the moment the child is gone
      # and nothing is pending. Without this the process died with the answer
      # still in its memory and the caller blocked on a newline the kernel then
      # discarded: `Unavailable` for a send that had actually completed.
      def drain_replies
        deadline = monotonic + REPLY_DRAIN_TIMEOUT
        until @close_after_drain.empty? || monotonic >= deadline
          queued = @close_after_drain.select { |io| @outbox.key?(io) }
          break if queued.empty?

          ready = IO.select(nil, queued, nil, POLL_INTERVAL)
          drain_outbox(ready ? ready[1] : [])
        end
      end

      # A client blocked on a reply that will now never come would hang until
      # its own timeout; tell it the session went away instead.
      def resolve_orphaned_pending
        return unless @pending

        settle_pending(@transcript.byteslice(@pending[:cursor]..) || '', settled: false, supervisor_exited: true)
      end

      # The process *group*, not just the child. PTY.spawn puts the child in its
      # own session, and agent CLIs routinely spawn workers (node wrappers, MCP
      # servers). Signalling only the recorded pid left those helpers running
      # after `rune session stop`, holding ptys and ports, where they could then
      # collide with the next session started for the same tool.
      def terminate_child
        return unless @child_pid

        kill_group(@child_pid)
        Process.wait(@child_pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def kill_group(pid)
        Process.kill('KILL', -pid)
      rescue Errno::ESRCH, Errno::EPERM
        # No such group, or not ours to signal — fall back to the single pid.
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
      end

      # Unregisters before closing. A closed descriptor left in @outbox (or
      # @attached) reaches the next IO.select, which raises IOError — unhandled
      # in the event loop, so the supervisor dies and its teardown SIGKILLs a
      # perfectly healthy child. Doing the bookkeeping here rather than at each
      # call site is what makes that unrepeatable.
      def safe_close(io)
        return if io.nil?

        @outbox.delete(io)
        @attached.delete(io)
        @accepted_at.delete(io)
        @clients.delete(io)
        @close_after_drain.delete(io)
        io.close unless io.closed?
      rescue IOError
        nil
      end

      def log_event(event, **fields)
        return unless @output_log

        @output_log.puts JSON.generate({ event: event, ts: Time.now.to_f }.merge(fields))
      # SystemCallError covers ENOSPC and friends: losing the transcript is bad,
      # losing the running session because the disk filled is worse.
      rescue IOError, SystemCallError
        nil
      end

      def positive_int(value, fallback)
        parsed = Integer(value)
        parsed.positive? ? parsed : fallback
      rescue TypeError, ArgumentError
        fallback
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    # rubocop:enable Metrics/ClassLength
  end
end
