# frozen_string_literal: true

require 'json'
require 'socket'
require 'fileutils'
require 'io/wait'
require 'shellwords'
require_relative 'store'
require_relative 'prompt_scanner'
require_relative 'pending_send'
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
      # Ceiling on a winsize arriving over the control socket. A pty's winsize
      # fields are 16-bit, so `{"op":"resize","rows":65535,"cols":65535}` is
      # accepted by the kernel — and once that size is recorded in meta, every
      # later `read --screen` allocates and drives a grid that big for the rest
      # of the session's life. CHG-0056 clamped the renderer against a single
      # hostile escape sequence in child output; leaving the recorded geometry
      # unbounded would reinstate the same denial of service one layer up, with
      # the amplification persisted to disk. Measured, one `read --screen` over
      # a 683KB `\e[999L` transcript: 0.76s at 40x120, 3.41s at this ceiling,
      # 17.72s at the 1000x2000 the renderer would clamp 65535 to.
      #
      # Well past any real terminal — a 6K panel at the smallest legible font is
      # roughly 240 rows by 600 columns — so nothing a human can actually resize
      # to is clamped, and a client that asks for more gets the largest size the
      # renderer can be trusted to draw rather than a refusal. The residual cost
      # at the ceiling is not eliminated, only bounded: line-insert and scroll
      # cost the renderer per row, so a genuinely 300-row terminal pays the same
      # 3.41s for the same hostile bytes.
      MAX_ROWS = 300
      MAX_COLUMNS = 1000
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
      #
      # 0.05 was tuned against Claude Code and silently failed against Kimi:
      # measured 3 of 3 sends where the prompt landed in Kimi's composer and was
      # never submitted, so `send` returned `settled: true` with only the echo
      # and the child sat waiting for a keystroke that had already been written.
      # Sending a bare carriage return afterwards submitted the queued text and
      # the answer appeared, which is what identified the delay rather than the
      # settle rule as the cause. At 0.30 and 0.80 it submits every time.
      #
      # 0.25 buys a 5x margin over the value that failed while staying an order
      # of magnitude under a model round trip. It is a race either way: the child
      # has to finish one read before the terminator arrives, and nothing here
      # can observe whether it did. A TUI slower than this will fail the same way
      # — which is why the failure now has a name in the docs instead of looking
      # like the settle bug.
      SUBMIT_DELAY = 0.25
      # Hard cap on a whole send, when the caller does not set one.
      DEFAULT_TIMEOUT_MS = 120_000
      UNDELIVERED_INPUT_ERROR = 'previous input is still being delivered to the child'
      # How long a failed rotation waits before it is attempted again. Each
      # attempt seeks and scans the tail it means to keep, and the condition
      # that failed it (an unwritable directory, a full disk) lasts longer than
      # one event, so retrying per event turns every log line into an 8MB scan.
      ROTATE_RETRY_SECONDS = 30.0
      # The point past which recording stops rather than growing. Reached only
      # when rotation cannot succeed at all — an unwritable directory, a full
      # disk that stays full — where the transcript would otherwise grow without
      # limit for the life of the session.
      HARD_LOG_CEILING = 2 * Store::MAX_LOG_BYTES
      # Written ahead of the first record to follow a write that failed. A write
      # that fails part-way leaves a fragment at the end of the file, and a
      # fragment can be a *complete* JSON object that simply never got its
      # newline — indistinguishable, once more text is appended, from a record
      # that landed. This makes it distinguishable: appended to any dangling
      # fragment it produces a line that cannot parse, so the reader skips it.
      # That is what lets "recorded" mean exactly "its own write returned".
      TORN_MARKER = "|torn\n"
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
        # A *window* onto the output, not all of it. Cursors stay absolute byte
        # offsets into the whole stream — `read` serves them client-side from
        # output.ndjson — so the supervisor only has to hold what it still uses:
        # the attach backlog and whatever the current send has produced.
        # Measured before this bound existed: resident memory tracked output
        # one-for-one, 27MB to 69MB in eighty seconds at 500KB/s, and never came
        # down. A persistent session is the entire feature, so unbounded growth
        # in the process that provides it is not a theoretical problem.
        @transcript = +''
        # What the child has produced since the in-flight send was last given a
        # tick. Accumulated as it arrives rather than sliced back out of the
        # transcript, because `byteslice` on a mutable String marks that String
        # *shared* — so the very next `<<` has to copy the whole buffer to make
        # it independent again. One copy of the entire turn, per 4 KB read.
        # Measured on a growing buffer: 16 MB costs 0.002s appended alone and
        # 4.46s when each append is followed by a byteslice of it, and a sampled
        # profile of a 24 MB turn put 85% of the supervisor inside that memmove.
        # It is also why the drain starved — 11.46 MB of a 12.00 MB answer read
        # in 90s — because the copy runs on the thread that pumps the pty.
        @fresh = +''
        @window_start = 0
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
        # Last winsize written to meta, so a repeated resize to the same shape
        # costs nothing.
        @rows = nil
        @cols = nil
        init_log_state
      end

      def run
        detach_from_terminal
        @output_log = @store.open_output(@name)
        @log_bytes = @store.output_size(@name)
        server = build_server
        reader, writer, pid = PTY.spawn(CHILD_ENV, *ExecArgv.for_spawn(@command, argv: true))
        @child_pid = pid
        @writer = writer
        # Recorded before anything else that could fail. A supervisor that dies
        # between the spawn and this write leaves a child nothing knows about:
        # `abandon` reads meta, finds no child_pid, and kills only the
        # supervisor. The window cannot be closed entirely — the pid does not
        # exist until spawn returns — but it should contain nothing but this.
        record_running(pid)
        record_child_identity(pid)
        apply_window_size(writer)
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

      # Bookkeeping for the transcript *file*, as opposed to the in-memory window
      # set up above. `@rotate_retry_at` is when a rotation that failed may be
      # attempted again; nil means no rotation has failed.
      def init_log_state
        @log_bytes = 0
        @rotate_retry_at = nil
        # Output bytes that never reached the transcript because a write failed,
        # nil while there is nothing owed. Carried, not forgotten: it is what the
        # next successful write records as a `truncated` event. Non-nil also
        # means the file may end mid-record, which is what gates TORN_MARKER.
        @log_gap = nil
      end

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
      #
      # Deliberately does *not* record the size it applies. Recording it would
      # write meta a second time immediately after `record_running`, widening a
      # read-modify-write window against the parent's own `update_meta` during
      # launch, and it buys nothing: an absent size renders at exactly these
      # dimensions, so `read --screen` is already right for a session nobody has
      # attached to. What it costs is the ability to tell "not recorded" from
      # "recorded as 40x120", which `screen_size_recorded` reports.
      def apply_window_size(writer)
        writer.winsize = [DEFAULT_ROWS, DEFAULT_COLUMNS]
      rescue IOError, SystemCallError, NoMethodError
        nil
      end

      def record_running(pid)
        @store.update_meta(@name, state: 'running', child_pid: pid, supervisor_pid: Process.pid)
      end

      # The child's start time as the OS reports it, which is what makes the
      # recorded pid identifiable later. Once this supervisor is gone, a bare
      # child pid cannot be told apart from a stranger that recycled the number,
      # and every question anyone asks of it afterwards — `list`, `archive` — is
      # really a question about that pair.
      #
      # Deliberately a second write rather than part of `record_running`: this
      # one shells out to `ps`, and the pid must reach disk before anything that
      # slow. A supervisor that dies in between simply leaves the field absent,
      # and an absent field is reported as "unknown", never as "orphaned".
      def record_child_identity(pid)
        started = Store.process_start_time(pid)
        @store.update_meta(@name, child_started_at: started) if started
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
      def pending_client = @pending ? [@pending.client] : []

      def discard_disconnected_pending(client)
        return unless client_gone?(client)

        @pending = nil
        # Defensive, and honestly labelled as such. A review claimed bytes
        # stranded here are handed to the next send; three attempts to
        # reproduce that failed, with and without the clear, so it is kept as
        # an invariant rather than as a fix for a demonstrated bug: @fresh is
        # meaningless once @pending is gone, and clearing it costs nothing.
        # Cleared in `begin_pending` too, so no future `@pending = nil` has to
        # remember.
        @fresh = +''
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
        # Only while a send is waiting, so nothing accumulates between turns:
        # `resolve_pending` empties this on the same tick, and appends stop
        # feeding it the moment that send is answered.
        @fresh << text if @pending
        trim_transcript
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
        enqueue(client, "#{JSON.generate(attached: true, cursor: transcript_bytes)}\n")
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
      # Reports what it did, not that it was asked. `resized: true` was a
      # constant: `{"op":"resize"}` with no arguments, with negative values, and
      # with `"tall"`/`"wide"` all answered `resized: true` while the session was
      # correctly left alone. A socket client could not tell whether its resize
      # took effect — reported from real use, and the kind of inconsistency that
      # matters more than any single bug, because a client author generalises
      # from whichever behaviour they meet first.
      def handle_resize(request, client, writer)
        applied = resize_child(writer, request[:rows], request[:cols])
        return respond(client, resized: true, rows: applied[0], cols: applied[1]) if applied

        respond(client, resized: false,
                        error: 'rows and cols must both be positive integers')
      end

      # Returns the size actually applied, or nil when the request was unusable.
      def resize_child(writer, rows, cols)
        rows = Integer(rows)
        cols = Integer(cols)
        return nil unless rows.positive? && cols.positive?

        # The child gets exactly the size it was given. Clamping before this
        # line reached the *pty*: attaching from a 400-row terminal silently
        # handed the child 300, so a TUI painted its top 300 rows forever and
        # nothing in the ack or the reply said so. The ceiling exists to bound
        # what rune later renders, which is rune's problem and not the child's.
        writer.winsize = [rows, cols]
        # SIGWINCH is what tells a TUI to re-lay-out; setting the size alone
        # leaves it drawing at the old geometry until something else repaints.
        # Skipped once the child is known gone: the pid may since belong to
        # something else entirely.
        Process.kill('WINCH', @child_pid) if @child_pid && !@child_finished
        record_window_size(rows, cols)
        [rows, cols]
      rescue TypeError, ArgumentError, IOError, SystemCallError, NoMethodError
        nil
      end

      # The geometry `read --screen` and `send --screen` must render at.
      #
      # Recorded in meta because those render in the *caller's* process, from
      # the transcript file, with no access to this pty — and the transcript
      # itself does not carry the size. Without this they rendered at a fixed
      # 40x120 for the whole time a human was attached from a terminal of any
      # other shape: measured through a real 30x100 attach, against the bytes
      # that terminal itself received, 29 of 30 rendered rows differed from what
      # the human was looking at, and 0 of 30 differ now.
      #
      # Written only when the size actually changes, and only cached once the
      # write succeeded. A human dragging a window edge emits a SIGWINCH per
      # frame, and each one would otherwise rewrite meta.json — a
      # read-modify-write of the whole file, on the thread that also has to keep
      # pumping the pty.
      # Recorded, and clamped at the record — the one place a ceiling belongs,
      # because rendering is the only thing it protects. A reduced value is
      # marked so `screen_size_recorded` can report false, which the spec
      # already promised and the code did not do: a supervisor-clamped size used
      # to come back flagged as trustworthy.
      def record_window_size(rows, cols)
        bounded_rows = [rows, MAX_ROWS].min
        bounded_cols = [cols, MAX_COLUMNS].min
        reduced = bounded_rows != rows || bounded_cols != cols
        return if @rows == bounded_rows && @cols == bounded_cols && @size_reduced == reduced
        return unless @store.update_meta(@name, rows: bounded_rows, cols: bounded_cols, size_reduced: reduced)

        @rows = bounded_rows
        @cols = bounded_cols
        @size_reduced = reduced
      end

      # Total bytes the child has ever produced. Cursors are offsets into that,
      # not into the window this process happens to still be holding.
      def transcript_bytes = @window_start + @transcript.bytesize

      # Everything from an absolute cursor onwards, as far as the window reaches.
      def slice_from(cursor)
        offset = cursor - @window_start
        return @transcript.dup if offset.negative?

        @transcript.byteslice(offset..).to_s
      end

      # Drops what nothing still needs: output older than the attach backlog and
      # older than any in-flight send's cursor. Never trims past a live cursor,
      # so a settle still returns everything that send produced however long the
      # turn ran.
      def trim_transcript
        floor = transcript_bytes - ATTACH_BACKLOG_BYTES
        floor = [floor, @pending.cursor].min if @pending
        return if floor <= @window_start

        @transcript = @transcript.byteslice((floor - @window_start)..).to_s
        @window_start = floor
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

      # The reason this send cannot be accepted, or nil to proceed. Grouped so
      # each reason is one line and adding another does not push the handler past
      # a complexity ceiling — the same shape `start_rejection` already uses.
      def send_rejection(request)
        return 'a send is already in flight on this session' if @pending
        return 'session child has exited' if @child_finished
        # A --no-wait send sets no @pending, so a second send can arrive while
        # the first is still draining into a backpressured pty. Accepting it
        # would force the previous terminator out alongside undelivered text.
        return UNDELIVERED_INPUT_ERROR if undelivered_input?
        # A send with no `text` key is malformed, and the most obvious mistake a
        # new socket client makes. It used to be accepted as an empty send, which
        # writes a bare carriage return, produces no output from most children,
        # and so waits out `timeout_ms` — 120 seconds by default. A client that
        # gave up after five seconds reported it as a hang, 3 of 3, noting that
        # every *other* malformed request got a clean error. That inconsistency
        # is worse for a protocol than any single bug, because a client author
        # generalises from whichever behaviour they meet first.
        #
        # `text: ""` stays valid: it is the documented way to deliver a bare
        # carriage return to a TUI holding text it never submitted. Absent and
        # empty are different requests.
        return 'send requires a text field (use "" to send a bare carriage return)' unless request.key?(:text)

        nil
      end

      def handle_send(request, client, writer)
        rejection = send_rejection(request)
        return respond(client, error: rejection) if rejection

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
        # `cursor` because --no-wait exists for exactly one pattern — fire the
        # task, then poll for output newer than the send — and it was the only
        # send mode that withheld the position marker that pattern needs. The
        # workaround was `read` for a cursor and then `send --no-wait`: two calls,
        # with a window where the child's output lands after the cursor but
        # before the task was sent. Reported from real use.
        return respond(client, sent: true, waited: false, cursor: transcript_bytes) if request[:no_wait]

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
        # terminator goes out now rather than after this text. Only reachable
        # once the previous text has drained — `handle_send` refuses otherwise,
        # because appending the terminator to still-queued text puts both in one
        # write and one read, which is the coalescing the delay exists to
        # prevent, reintroduced by the guard meant to preserve ordering.
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
        # Text still queued: restart the clock rather than merely waiting. The
        # deadline is measured from the last text byte actually going out, not
        # from when the send arrived — `drain_outbox` and this run in the same
        # tick, so a deadline already in the past would fire microseconds after
        # the tail drained and land in the child's same read. That is precisely
        # the coalescing the delay exists to prevent, and backpressure on the
        # pty is when it would have been reintroduced.
        return @submit_at = monotonic + SUBMIT_DELAY if pending_text?

        flush_submit
      end

      def pending_text? = @outbox.key?(@writer) && !@outbox[@writer].empty?

      # A previous send whose text has not finished going out, and whose
      # terminator is therefore still owed.
      def undelivered_input? = !@submit_at.nil? && pending_text?

      def flush_submit
        return if @submit_at.nil?

        @submit_at = nil
        enqueue(@writer, "\r") if @writer && !@child_finished
      end

      # The cursor is taken here, before waiting, so the reply contains only
      # what this send produced. Without it a banner or a previous command's
      # trailing output would be misattributed to this request.
      def begin_pending(request, client, echo)
        @fresh = +''
        settle_ms = positive_int(request[:settle_ms], DEFAULT_SETTLE_MS)
        @pending = PendingSend.new(
          client: client, cursor: transcript_bytes, echo: echo, now: monotonic,
          settle_ms: settle_ms, timeout_ms: positive_int(request[:timeout_ms], DEFAULT_TIMEOUT_MS),
          regex: PendingSend.compile_regex(request[:wait_for_regex]),
          busy_at_send: child_still_talking?(settle_ms)
        )
      end

      # The send is fed what is *new* each tick, never everything it has
      # produced — that was quadratic twice over, once in the copy that built
      # the slice and once in `PendingSend` re-reading it. The full slice is
      # still what settles the send; it is built once, here, on the tick that
      # answers it.
      #
      # Fed even when nothing arrived: the echo grace window expiring is a
      # decision in its own right, and a child that falls silent mid-echo has to
      # reach it without waiting for a byte that is not coming.
      def resolve_pending
        return unless @pending

        now = monotonic
        @pending.absorb(@fresh, now: now)
        @fresh = +''
        outcome = @pending.outcome(now: now, child_finished: @child_finished,
                                   submitted: @submit_at.nil?, last_output_at: @last_output_at)
        settle_pending(slice_from(@pending.cursor), **outcome) if outcome
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
        respond(pending.client, {
          output: slice,
          cursor: transcript_bytes,
          prompt_detected: PromptScanner.prompt_at_end?(slice),
          busy_at_send: pending.busy_at_send
        }.merge(flags).merge(gap_field))
      end

      # Present only while a hole is still owed, which is the one window in which
      # `read` cannot report it: until a write succeeds there is nowhere on disk
      # to record the gap, so the supervisor's memory is the only place the skew
      # is known at all. On a send's reply because that is where the caller is
      # handed the cursor the skew makes unresolvable.
      def gap_field = @log_gap ? { transcript_gap_bytes: @log_gap } : {}

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
          cursor: transcript_bytes
        }.merge(gap_field)
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
      # Bounded on disk as well as in memory. The in-memory window stopped
      # resident memory tracking output, but the transcript file kept every byte
      # for the life of the session and `archive` preserved it, so the cost
      # outlived the session that paid it.
      def rotate_log
        return if @rotate_retry_at && monotonic < @rotate_retry_at

        @output_log = @store.rotate_output(@name, @output_log, transcript_bytes)
        @log_bytes = @store.output_size(@name)
        @rotate_retry_at = nil
      # Backed off rather than retried on the next event: @log_bytes stays over
      # the ceiling while the condition lasts, and each attempt seeks and scans
      # the tail it means to keep. Recording itself continues either way, into
      # the oversized file — `writable_log` reopens the handle the failed
      # rotation closed.
      rescue IOError, SystemCallError
        @rotate_retry_at = monotonic + ROTATE_RETRY_SECONDS
      end

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
        exit_status(status)
      rescue Errno::ECHILD
        0
      end

      def exit_status(status) = status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)

      # Each step is isolated: teardown previously shared one rescue, so a child
      # that would not die took the socket removal and the file descriptors down
      # with it, leaving a stale control socket that later clients connect to and
      # get ECONNREFUSED from instead of a clean "not running" result.
      def cleanup(server)
        [
          -> { resolve_orphaned_pending },
          -> { drain_replies },
          # The child goes first, and the record of its death second. The other
          # order wrote `state: 'exited'` while the child was still running, so a
          # supervisor that died in that window — the abnormal teardowns that
          # reach here, where `conclude` never ran — left a concluded record next
          # to a live process. Anything reading meta then believed a session was
          # over while its child held a pty, and any check that trusted the state
          # field was blind to exactly the case it existed for.
          #
          # `conclude` already kills before recording on the normal path, so this
          # only aligns teardown with it; `terminate_child` is idempotent, and
          # each step here has its own rescue, so a child that will not die still
          # gets the record written after it.
          -> { terminate_child },
          # Whatever brought us here, the session is over. Leaving meta saying
          # "running" makes every later command report a session that is not
          # there, with no exit code to explain it — and `list` then shows a
          # live session backed by nothing.
          -> { finish(EXIT_SUPERVISOR_CRASHED) unless @finished },
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

        settle_pending(slice_from(@pending.cursor), settled: false, supervisor_exited: true)
      end

      # The process *group*, not just the child. PTY.spawn puts the child in its
      # own session, and agent CLIs routinely spawn workers (node wrappers, MCP
      # servers). Signalling only the recorded pid left those helpers running
      # after `rune session stop`, holding ptys and ports, where they could then
      # collide with the next session started for the same tool.
      def terminate_child
        return unless @child_pid

        kill_group(@child_pid)
        # Keeps the status it waited for. Discarding it meant `conclude` then
        # called `reap`, whose `Process.wait2` raised ECHILD on an already-reaped
        # child and returned a hardcoded 0 — so a session killed on `stop`
        # recorded `exit_code: 0`, telling `list` and any inspecting tool that
        # the child had exited cleanly.
        _, status = Process.wait2(@child_pid)
        @exit_code = exit_status(status)
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

      # SystemCallError covers ENOSPC and friends: losing the transcript is bad,
      # losing the running session because the disk filled is worse. But a write
      # that fails is now *recorded*, not merely survived. The in-memory cursor
      # has already advanced — those bytes really were produced — so a hole
      # nothing accounts for makes every cursor `send` hands out unresolvable by
      # `read`, permanently. Reproduced on a real full filesystem (RUNE_HOME on a
      # 20MB ramdisk): 852_000 bytes of output went unrecorded, the transcript
      # reported `dropped: 0`, and freeing the disk made it worse, because
      # logging resumed over the hole without a word.
      #
      # The lost bytes are carried until a write succeeds and then emitted as a
      # `truncated` event — the same vehicle rotation already uses to keep cursors
      # absolute, so `read` resolves a pre-hole cursor again and reports
      # `dropped_bytes` instead of silently returning less.
      def log_event(event, **fields)
        # Checked before the record is generated, not inside `append_log`:
        # serializing an `output` event materializes the child's text into a JSON
        # string, which is the single most expensive thing on this path, and
        # there is no point paying it for a write that cannot happen.
        # `writable_log`, not the bare predicate: it is the same cheap check when
        # the handle is open, and it is also the only path that reopens one that
        # went away. Guarding on the predicate alone made recovery unreachable —
        # once a rotation failed, every later event became gap forever.
        return note_log_gap(event, fields) unless writable_log
        # The documented bound has to survive a rotation that cannot succeed.
        # Before gap recording, a failed rotation closed the handle and every
        # later write was swallowed — ugly, but the cap held. Recording through
        # the failure removed the swallowing and with it the bound: measured
        # against an unwritable directory, the transcript reached 42,614,387
        # bytes past a 32MB cap and was still climbing, while docs/sessions.md
        # promised "a session left running for a day does not grow without
        # limit". Past the hard ceiling the bytes become gap instead, so growth
        # stops, the accounting stays exact, and the next rotation that does
        # succeed emits them as `truncated`.
        return note_log_gap(event, fields) if @log_bytes >= HARD_LOG_CEILING

        line = JSON.generate({ event: event, ts: Time.now.to_f }.merge(fields))
        written = append_log(line)
        return note_log_gap(event, fields) unless written

        @log_bytes += written
        rotate_log if @log_bytes >= Store::MAX_LOG_BYTES
      end

      def writable_log? = !(@output_log.nil? || @output_log.closed?)

      # Bytes appended, or nil if the event did not reach the file. Any pending
      # gap goes first and as its own write: one record per write is what makes
      # "recorded" mean "its own write returned", because a write that fails
      # part-way can leave at most the record it was writing unfinished — and
      # TORN_MARKER then makes that leftover unreadable rather than letting it be
      # counted a second time when the gap is retried.
      def append_log(line)
        log = @output_log
        return nil unless log

        gap = @log_gap ? write_record(log, gap_line) : 0
        return nil unless gap

        written = write_record(log, line)
        written && (gap + written)
      end

      # One NDJSON record, preceded by the torn marker when the last write
      # failed. Returns bytes written, or nil when nothing can be trusted to have
      # landed.
      def write_record(log, record)
        payload = @log_gap ? "#{TORN_MARKER}#{record}\n" : "#{record}\n"
        log.write(payload)
        @log_gap = nil
        payload.bytesize
      rescue IOError, SystemCallError
        nil
      end

      def gap_line = JSON.generate(event: 'truncated', ts: Time.now.to_f, dropped_bytes: @log_gap)

      # Only `output` events carry stream bytes, so only they widen the hole. A
      # lost `start`/`exit` still opens one, at zero bytes, because a reader must
      # not inherit a transcript with events missing from the middle and no sign
      # of it — and because a zero-byte gap is still the flag that says the file
      # may end mid-record.
      def note_log_gap(event, fields)
        @log_gap = (@log_gap || 0) + (event == 'output' ? fields[:bytes].to_i : 0)
        nil
      end

      # Recording must not stop for the life of a session because a handle went
      # away: a rotation that fails after closing the old handle used to leave
      # the supervisor writing to a closed file it had no idea was closed, and
      # every later write was swallowed. Nothing is created out of nothing — the
      # directory is gone once a session is archived, so this simply fails and
      # the gap keeps accumulating.
      # Only ever reopens the transcript this supervisor owns. Reopening by name
      # is otherwise a door into a *successor*: a supervisor that outlived its
      # session, or lost the race to a `start` reusing the name, would append its
      # child's output into the new session's transcript, where it would read as
      # that child's. The meta check costs one read on a recovery path that runs
      # at most once per outage, and makes that impossible rather than unlikely.
      def writable_log
        return @output_log if @output_log && !@output_log.closed?

        # Absent means this supervisor has not finished starting — its own pid is
        # written once the pty exists — so an absent value is ours by default.
        # Only a pid belonging to somebody else is a refusal.
        owner = @store.read_meta(@name)&.dig(:supervisor_pid)
        return nil if owner && owner != Process.pid

        @output_log = @store.open_output(@name)
      rescue IOError, SystemCallError
        @output_log = nil
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
