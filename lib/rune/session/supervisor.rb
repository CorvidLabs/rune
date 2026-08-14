# frozen_string_literal: true

require 'json'
require 'socket'
require 'fileutils'
require 'io/wait'
require 'shellwords'

# IO#winsize= comes from this stdlib extension. Rescued on LoadError the same
# way pty_runner.rb rescues 'pty' and pty_watcher.rb rescues 'io/console':
# expected almost everywhere, guaranteed nowhere.
begin
  require 'io/console'
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
        @stopping = false
        @exit_code = nil
      end

      def run
        detach_from_terminal
        @output_log = @store.open_output(@name)
        server = build_server
        reader, writer, pid = PTY.spawn(CHILD_ENV, *@command)
        @child_pid = pid
        apply_window_size(writer)
        record_running(pid)
        log_event('start', command: Shellwords.join(@command), pid: pid)
        event_loop(server, reader, writer)
      rescue Errno::ENOENT, Errno::EACCES => e
        # Same convention PTYRunner/PTYWatcher use: a missing (127) or
        # non-executable (126) target is the child's exit status, not a
        # supervisor-level crash.
        finish(e.is_a?(Errno::ENOENT) ? 127 : 126)
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
        FileUtils.rm_f(path)
        server = Store.with_bindable_path(path) { |bindable| UNIXServer.new(bindable) }
        File.chmod(Store::FILE_MODE, path)
        server
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
          ready = IO.select([server, reader, *@clients, *@attached], nil, nil, POLL_INTERVAL)
          dispatch_ready(ready, server, reader, writer) if ready
          resolve_pending
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
          elsif @attached.include?(io)
            forward_from_attached(io, writer)
          else
            @clients.delete(io)
            handle_request(io, writer)
          end
        end
      end

      def accept_client(server)
        @clients << server.accept_nonblock
      rescue IO::WaitReadable, Errno::ECONNABORTED
        nil
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
        return if @attached.empty?

        @attached.dup.each do |client|
          client.write(text)
          client.flush
        rescue IOError, SystemCallError
          @attached.delete(client)
          safe_close(client)
        end
      end

      # After the ack line the socket stops being a request/reply channel and
      # becomes a raw duplex pipe to the pty, which is what lets a human type
      # into a session an agent started.
      def handle_attach(client)
        client.puts(JSON.generate(attached: true, cursor: @transcript.bytesize))
        client.flush
        client.write(recent_transcript)
        client.flush
        @attached << client
      rescue IOError, SystemCallError
        safe_close(client)
      end

      # Replayed on attach so the terminal shows the session's current screen
      # instead of an empty one until the child happens to repaint.
      def recent_transcript
        @transcript.byteslice([@transcript.bytesize - ATTACH_BACKLOG_BYTES, 0].max..).to_s.scrub
      end

      def forward_from_attached(client, writer)
        chunk = client.read_nonblock(READ_CHUNK)
        writer.write(chunk)
        writer.flush
      rescue IO::WaitReadable
        nil
      rescue IOError, SystemCallError
        @attached.delete(client)
        safe_close(client)
      end

      # ---- control protocol: one JSON request line in, one JSON reply line out

      def handle_request(client, writer)
        line = client.gets
        return client.close if line.nil?

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

      def dispatch(request, client, writer)
        case request[:op]
        when 'send' then handle_send(request, client, writer)
        when 'status' then respond(client, status_payload)
        when 'attach' then handle_attach(client)
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
      def write_to_child(writer, request)
        text = request[:text].to_s
        text += "\r" unless request[:no_newline]
        writer.write(text)
        writer.flush
        text
      end

      # The cursor is taken here, before waiting, so the reply contains only
      # what this send produced. Without it a banner or a previous command's
      # trailing output would be misattributed to this request.
      def begin_pending(request, client, echo)
        settle_ms = positive_int(request[:settle_ms], 800)
        timeout_ms = positive_int(request[:timeout_ms], 120_000)
        @pending = {
          client: client,
          cursor: @transcript.bytesize,
          settle_ms: settle_ms,
          regex: compile_regex(request[:wait_for_regex]),
          deadline: monotonic + (timeout_ms / 1000.0),
          echo: echo,
          sent_at: monotonic,
          saw_output: false
        }
      end

      def compile_regex(source)
        source.nil? || source.empty? ? nil : Regexp.new(source)
      rescue RegexpError
        nil
      end

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
        return { settled: true, matched: true } if @pending[:regex]&.match?(slice)
        return { settled: false, timed_out: true } if monotonic >= @pending[:deadline]
        return { settled: true, child_exited: true } if @child_finished
        return { settled: true } if quiet_enough?

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
        # The echo arrives in chunks, so mid-arrival the slice is a *prefix* of
        # the echo rather than starting with it. Without this case a partial
        # echo reads as real output and settles the send immediately — which is
        # exactly how this first presented.
        #
        # Time-bounded, because "output so far is a prefix of what I sent" is
        # ambiguous: it is a half-arrived echo, or it is a complete reply that
        # happens to be a prefix of the prompt. Treating the second case as an
        # echo hung the send until --timeout-ms (send "helloworld" to a
        # non-echoing child that answers "hello"). A real echo always lands
        # inside the grace window, so after it a prefix is taken as real output.
        return '' if echo.start_with?(normalized) && within_echo_grace?
        return normalized unless normalized.start_with?(echo)

        normalized[echo.length..].to_s
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

      def settle_pending(slice, **flags)
        pending = @pending
        @pending = nil
        respond(pending[:client], {
          output: slice,
          cursor: @transcript.bytesize,
          prompt_detected: PromptScanner.prompt_at_end?(slice)
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

      def respond(client, payload)
        client.puts(JSON.generate(payload))
        client.flush
      rescue Errno::EPIPE, IOError
        nil
      ensure
        safe_close(client)
      end

      # ---- teardown

      def finish(exit_code)
        @exit_code = exit_code
        @store.update_meta(@name, state: 'exited', exit_code: exit_code, exited_at: Time.now.to_f)
        log_event('exit', exit_code: exit_code)
      end

      def reap
        return nil unless @child_pid

        _, status = Process.wait2(@child_pid)
        status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
      rescue Errno::ECHILD
        0
      end

      def cleanup(server)
        resolve_orphaned_pending
        terminate_child
        (@clients + @attached).each { |client| safe_close(client) }
        safe_close(server)
        FileUtils.rm_f(@store.socket_path(@name))
        @output_log&.close
      rescue StandardError
        nil
      end

      # A client blocked on a reply that will now never come would hang until
      # its own timeout; tell it the session went away instead.
      def resolve_orphaned_pending
        return unless @pending

        settle_pending(@transcript.byteslice(@pending[:cursor]..) || '', settled: false, supervisor_exited: true)
      end

      def terminate_child
        return unless @child_pid

        Process.kill('KILL', @child_pid)
        Process.wait(@child_pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def safe_close(io)
        io&.close unless io.nil? || io.closed?
      rescue IOError
        nil
      end

      def log_event(event, **fields)
        return unless @output_log

        @output_log.puts JSON.generate({ event: event, ts: Time.now.to_f }.merge(fields))
      rescue IOError, Errno::EPIPE
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
