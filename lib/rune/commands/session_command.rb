# frozen_string_literal: true

require 'rbconfig'
require 'timeout'
require_relative '../session/store'
require_relative '../session/transcript'
require_relative '../session/client'
require_relative '../session/supervisor'
require_relative '../session/attachment'
require_relative '../output_limiter'

module Rune
  module Commands
    # rubocop:disable Metrics/ClassLength -- one class per subcommand would scatter a single
    # user-facing surface (`rune session ...`) across five files that all share the same store,
    # name validation, and error vocabulary; kept together for the same reason pty_watcher.rb
    # keeps its lifecycle in one place.
    class SessionCommand < Command
      name 'session'
      summary 'Start and drive persistent named PTY sessions that outlive a single rune invocation'
      usage 'rune session <start|send|read|attach|list|stop|archive> [--name=NAME] [options]'
      flag '--name=NAME',
           'Session name. Optional for start (an unused <tool>-<word> codename is generated); ' \
           'required by send/read/attach/stop.'
      flag '--settle-ms=N', 'send: return once the child has been quiet for N ms (default 800).'
      flag '--timeout-ms=N', 'send: hard cap on the whole wait (default 120000).'
      flag '--wait-for-regex=RE',
           'send: wait for output matching RE. Replaces the settle window rather than racing it — ' \
           'the send then answers on a match, the child exiting, or --timeout-ms, and reports matched.'
      flag '--no-wait', 'send: write the input and return immediately, without waiting for a reply.'
      flag '--no-newline',
           'send: do not append the trailing carriage return that submits the line (Enter is CR, ' \
           'which is what raw-mode TUIs listen for).'
      flag '--since=CURSOR', 'read: return only transcript bytes at or after this cursor.'
      flag '--screen',
           'send/read: also return the rendered terminal screen. A full-screen agent repaints, so ' \
           'the byte stream holds every frame while the screen holds only what is displayed.'
      flag '--tail=N', 'send/read: keep only the last N lines, where CR ends a line as well as LF.'
      flag '--grep=RE',
           'send/read: keep only lines matching RE, from the ANSI-stripped transcript — the ' \
           'repaint stream with escapes removed, counting CR as a line break. This is NOT the ' \
           'rendered screen: overwritten history still matches and comes back as a clean line, ' \
           'and a cursor-painted frame is one long line, so --context is inert and a match can ' \
           'return the whole frame. Use --screen when you need what is currently displayed. ' \
           'A pattern that will not compile selects nothing and is reported as grep_error.'
      flag '--context=N', 'read: lines of context to keep either side of a --grep match (default 0).'
      flag '--max-output=BYTES',
           'send/read: bound the returned text to BYTES of transcript, keeping head and tail. The ' \
           'join is marked in the text with a `[rune] ==== N bytes omitted by --max-output ====` ' \
           'line, which is rune\'s annotation rather than transcript and is not charged to BYTES. ' \
           'Bounds output/clean_output only: --screen is bounded by geometry instead, at most ' \
           'screen_rows x (screen_cols + 1), both returned in the same reply.'
      flag '--all-projects', 'list: include sessions from every project, not just this one.'
      flag '--archived', 'list: show archived sessions instead of live ones.'

      subcommand 'start',   'Start a named session that outlives this invocation and keeps its child alive.'
      subcommand 'send',    'Send text to the child and wait for it to settle, match a regex, or time out.'
      subcommand 'read',    'Read transcript output, optionally since a cursor, as a screen, or grepped.'
      subcommand 'attach',  'Attach this terminal to a running session as a live bidirectional view.'
      subcommand 'list',    'List sessions with state, exit code, and recent activity.'
      subcommand 'stop',    'Stop a session, ending its child and supervisor.'
      subcommand 'archive', 'Archive a stopped session, retaining its transcript.'

      SUBCOMMANDS = %w[start send read attach list stop archive].freeze
      # How long `start` waits for the supervisor to come up and report ready
      # before giving up. Generous because it covers a Ruby process boot.
      START_TIMEOUT = 10.0
      # How long `stop` waits for a cooperative shutdown before force-killing.
      GRACEFUL_STOP_TIMEOUT = 3.0
      # How much of a transcript's tail `list` reads to report recent activity.
      ACTIVITY_TAIL_BYTES = 8192
      ACTIVITY_LINE_LIMIT = 100
      # How long `stop` waits for SIGKILLed processes to actually disappear.
      DEATH_TIMEOUT = 3.0
      # Mirrors the supervisor's own default so a caller's ceiling is never
      # tighter than the wait it asked for.
      DEFAULT_SEND_TIMEOUT_MS = 120_000
      CLIENT_TIMEOUT_MARGIN = 15.0
      # How many codenames a start without --name will try before giving up.
      # Each retry is another process having claimed the one it picked.
      # A shell reports 127 for a command it could not find, so a child that exits 127 before the
      # session is even ready never ran.
      EXEC_FAILURE_STATUS = 127

      GENERATED_NAME_ATTEMPTS = 5

      VALUE_FLAGS = {
        name: [/\A--name=(.*)\z/, :string],
        home: [/\A--home=(.*)\z/, :string],
        project: [/\A--project=(.*)\z/, :string],
        wait_for_regex: [/\A--wait-for-regex=(.*)\z/, :string],
        settle_ms: [/\A--settle-ms=(.*)\z/, :positive_int],
        timeout_ms: [/\A--timeout-ms=(.*)\z/, :positive_int],
        since: [/\A--since=(.*)\z/, :non_negative_int],
        tail_lines: [/\A--tail=(.*)\z/, :positive_int],
        grep: [/\A--grep=(.*)\z/, :string],
        context_lines: [/\A--context=(.*)\z/, :non_negative_int],
        max_output_bytes: [/\A--max-output=(.*)\z/, :positive_int]
      }.freeze
      ALIASES = {
        tail_lines: '--tail', max_output_bytes: '--max-output', context_lines: '--context'
      }.freeze

      BOOLEAN_FLAGS = {
        '--no-wait' => :no_wait, '--no-newline' => :no_newline,
        '--all-projects' => :all_projects, '--archived' => :archived,
        '--screen' => :screen
      }.freeze

      # Every long flag this command answers to, for the "did you mean" in `unknown_flag_error`.
      # Built from the same three tables the parser uses, and carrying both spellings
      # `separate_form?` accepts, so a flag cannot be added without appearing here.
      KNOWN_FLAGS = (
        BOOLEAN_FLAGS.keys +
        VALUE_FLAGS.keys.flat_map { |key| [ALIASES[key], "--#{key.to_s.tr('_', '-')}"] }
      ).compact.uniq.freeze

      # `_supervise` is deliberately absent from SUBCOMMANDS: it is how `start`
      # re-invokes rune as the detached supervisor, so it must dispatch but must
      # never appear in help or in an error's list of valid subcommands.
      DISPATCH = {
        'start' => :start, 'send' => :send_input, 'read' => :read_transcript,
        'attach' => :attach, 'list' => :list, 'stop' => :stop,
        'archive' => :archive_session, '_supervise' => :supervise
      }.freeze

      def call(args, _options)
        remaining = args.dup
        handler = DISPATCH[remaining.shift]
        return unknown_subcommand(args.first) unless handler

        send(handler, remaining)
      end

      def human_render(data, io)
        case data[:action]
        when 'list' then render_list(data, io)
        when 'send', 'read' then render_output(data, io)
        when 'archive' then render_archive(data, io)
        else io.puts(JSON.generate(data.except(:action)))
        end
      end

      # The orphan warning is printed after the archive line rather than folded
      # into the JSON blob, because this is the last moment the pid is reachable
      # by name and a human skimming a one-line envelope would miss it.
      def render_archive(data, io)
        io.puts(JSON.generate(data.except(:action, :orphaned_child_pid)))
        return unless data[:orphaned_child_pid]

        io.puts "\e[33m! child pid #{data[:orphaned_child_pid]} is still running and this session no " \
                "longer names it. Check it with 'ps -p #{data[:orphaned_child_pid]}'.\e[0m"
      end

      # A human reading a driven TUI agent wants the stripped text, not its
      # repaint traffic; agent mode still gets both fields in the envelope.
      #
      # `grep_error` is printed first because the text below it is empty when a
      # pattern would not compile: a bare blank line with no reason for it is a
      # worse answer than the whole transcript this used to print.
      def render_output(data, io)
        io.puts("\e[31m✗ #{data[:grep_error]}\e[0m") if data[:grep_error]
        io.puts(data[:clean_output] || data[:output])
      end

      private

      def unknown_subcommand(subcommand)
        if subcommand.nil?
          Result.failure("No subcommand given. Usage: rune session <#{SUBCOMMANDS.join('|')}> [options]")
        else
          Result.failure("Unknown session subcommand: #{subcommand}. Expected one of: #{SUBCOMMANDS.join(', ')}.")
        end
      end

      # ---- start

      def start(args)
        options, rest, error = extract_options(args, operand_owns_flags: true)
        return Result.failure(error) if error

        command = rest.first == '--' ? rest[1..] : rest
        rejection = start_rejection(options, command)
        return rejection if rejection

        return serialized_launch(options[:name], command) if options[:name]

        launch_generated(command)
      end

      # A generated name is chosen inside the lock and retried on contention.
      # Choosing it outside meant two `start -- grok` racing each other both
      # landed on `grok-amber`: the lock kept them from damaging each other, but
      # the loser failed on a name it never asked for while a dozen other
      # codenames were free — exactly the parallel-agent case an optional name
      # exists for. The losing attempt reuses the winner's directory, so
      # retrying costs nothing and `generate_name` skips it next time round.
      def launch_generated(command)
        GENERATED_NAME_ATTEMPTS.times do
          name = store.generate_name(command)
          outcome = store.with_start_lock(name) do
            running_conflict(name) ? :taken : launch(name, command)
          end
          return outcome unless %i[busy taken].include?(outcome)
        end

        Result.failure("Could not claim a session name for #{command.first.inspect} after " \
                       "#{GENERATED_NAME_ATTEMPTS} attempts. Retry, or pass --name.")
      end

      # The conflict check has to happen inside the lock, not before it: two
      # starts racing each other both passed a check made outside it, and the
      # second then unlinked the first's socket and left its child orphaned.
      def serialized_launch(name, command)
        outcome = store.with_start_lock(name) do
          conflict = running_conflict(name)
          conflict || launch(name, command)
        end
        return outcome unless outcome == :busy

        Result.failure("Session #{name.inspect} is being started by another process.")
      end

      def start_rejection(options, command)
        if command.empty?
          return Result.failure('No command specified. Usage: rune session start [--name=NAME] -- <command...>')
        end
        unless options[:name].nil? || Session::Store.valid_name?(options[:name])
          return Result.failure(name_error(options[:name]))
        end
        return Result.failure('PTY unavailable: pty stdlib failed to load.') unless PTYRunner.pty_available?

        # Cheap early rejection; the authoritative check runs inside the start
        # lock, where it cannot be raced. Only for an explicit name — a
        # generated one is picked inside that lock and retried, so there is
        # nothing here to reject.
        options[:name] ? running_conflict(options[:name]) : nil
      end

      def running_conflict(name)
        return nil unless store.exist?(name)

        meta = store.read_meta(name)
        return nil unless meta && Session::Store.alive?(meta[:supervisor_pid])

        # The pid is shown only once one exists: during a start race the winner
        # records its state before either pid is known, and "(pid )" reads like
        # a bug rather than the timing detail it is.
        pid = meta[:child_pid] || meta[:supervisor_pid]
        Result.failure("Session #{name.inspect} is already running#{" (pid #{pid})" if pid}. " \
                       'Stop it first or choose another name.')
      end

      def launch(name, command)
        store.create(name)
        # One transcript per supervisor lifetime. Reusing a name kept appending
        # to the previous run's output.ndjson while the new supervisor's cursors
        # restarted at zero, so `send` cursors and `read` offsets silently
        # disagreed and `read` replayed a dead session's output as if it were
        # this one's — a direct break of the cursor-agreement invariant.
        store.reset_transcript(name)
        store.write_meta(name, name: name, command: command, state: 'starting', started_at: Time.now.to_f)
        pid = spawn_supervisor(name, command)
        # Recorded before waiting, so a second `start` racing this one sees a
        # live supervisor instead of a `starting` record with no pid — which
        # `running_conflict` read as "free" for the whole interpreter boot.
        store.update_meta(name, supervisor_pid: pid)
        ready_error = await_ready(name, pid)
        if ready_error
          # Without this the supervisor spawned just above keeps running after
          # `start` reports failure, holding a pty for a session the caller was
          # told does not exist — found by checking for stray processes after a
          # `start` that failed on an unrelated bug, not by a test.
          abandon(name, pid)
          return Result.failure(ready_error)
        end

        meta = store.read_meta(name) || {}
        # `project` because a session's namespace is the cwd's basename plus a
        # hash, so every git worktree is a separate one. A caller that started a
        # session in a worktree and read from the parent repo got
        # "No such session", and `list` — the remedy the error suggests — showed
        # an empty array, actively confirming the wrong conclusion. Reported by
        # someone who was about to debug the wrong program.
        payload = { action: 'start', name: name, command: command, project: store.project,
                    child_pid: meta[:child_pid], supervisor_pid: pid,
                    state: meta[:state], exit_code: meta[:exit_code] }.compact
        launch_failure(name, meta) || Result.success(payload)
      end

      # A launch that never happened is a failure, not a success with a field to check.
      #
      # `start -- a_binary_that_is_not_there` returned `status: "ok"` with `state: "exited"` and
      # `exit_code: 127`, so a caller checking `status` — the field whose entire job is to say
      # whether the call worked — saw success. It was documented as a gotcha ("check `state`"),
      # which is the wrong shape of answer: an envelope should not need a footnote to be read
      # correctly. Reported from a real 22-minute drive, where it cost an hour.
      #
      # Only 127 fails, deliberately. `start -- true` exits 0 immediately and that is a *successful*
      # launch of a program that had nothing to do; treating any prompt exit as a failure would
      # break every short-lived child. 127 is the shell's "command not found", which is the one
      # case where the child never ran at all.
      def launch_failure(name, meta)
        return nil unless meta[:exit_code] == EXEC_FAILURE_STATUS

        abandon(name, meta[:supervisor_pid])
        Result.failure("Could not start #{name.inspect}: the command exited #{EXEC_FAILURE_STATUS} " \
                       'immediately, which is what a shell reports for a command that is not on PATH. ' \
                       'Check the command name and that it is installed.')
      end

      # Re-invokes rune's own executable rather than forking in-process: a fork
      # would inherit this process's whole VM state (open fds, signal traps,
      # RSpec's own runtime under test), and the supervisor needs a clean one.
      # `bin/rune` uses require_relative, so this resolves correctly both from a
      # source checkout and from an installed gem, where bin/ is packaged.
      def spawn_supervisor(name, command)
        log_path = File.join(store.session_dir(name), 'supervisor.log')
        pid = File.open(log_path, File::WRONLY | File::CREAT | File::APPEND, Session::Store::FILE_MODE) do |log|
          Process.spawn(
            RbConfig.ruby, executable_path, 'session', '_supervise',
            "--name=#{name}", "--home=#{store.home}", "--project=#{store.project}", '--', *command,
            in: File::NULL, out: File::NULL, err: log, pgroup: true
          )
        end
        Process.detach(pid)
        pid
      end

      def executable_path = File.expand_path('../../../bin/rune', __dir__)

      # Tears down a supervisor that was spawned but never became usable, so a
      # failed `start` leaves nothing behind. Reuses the same tolerant kill
      # path as `stop`, since the pids may already be gone.
      def abandon(name, supervisor_pid)
        meta = store.read_meta(name) || {}
        kill_remaining(meta.merge(supervisor_pid: supervisor_pid))
        store.update_meta(name, state: 'failed', failed_at: Time.now.to_f)
      end

      # `start` must not return before the session can actually be sent to,
      # otherwise the very next `rune session send` races the supervisor's boot
      # and fails against a socket that does not exist yet.
      #
      # A child that has already exited is a *ready* outcome, not a startup
      # error: a short-lived command legitimately runs to completion faster
      # than this can observe it (`bash -c 'exit 7'` reliably beats the first
      # poll, since the poll only begins after a Ruby interpreter boot). This
      # also keeps the missing/non-executable case consistent with `rune run`
      # and `rune watch`, where 127/126 is the child's exit status on a
      # successful Result rather than a rune-level failure.
      def await_ready(name, supervisor_pid)
        deadline = monotonic + START_TIMEOUT
        while monotonic < deadline
          verdict = readiness(name, supervisor_pid)
          return verdict == :ready ? nil : verdict if verdict

          sleep 0.02
        end
        "Session #{name.inspect} did not become ready within #{START_TIMEOUT.to_i}s."
      end

      # :ready, an error string, or nil to keep waiting.
      def readiness(name, supervisor_pid)
        meta = store.read_meta(name)
        return :ready if meta && (serving?(name, meta) || meta[:state] == 'exited')
        # A supervisor that died before recording anything never will, so
        # waiting out START_TIMEOUT only delays an error that is already certain.
        return supervisor_died(name) unless Session::Store.alive?(supervisor_pid)

        nil
      end

      # Liveness as well as recorded state: a supervisor can write `running`,
      # create the socket, then die on an early exception. Without the pid check
      # `start` reported success and the caller's very next `send` failed against
      # a session it had just been told was up.
      def serving?(name, meta)
        meta[:state] == 'running' &&
          File.socket?(store.socket_path(name)) &&
          Session::Store.alive?(meta[:supervisor_pid])
      end

      def supervisor_died(name)
        "Session #{name.inspect} supervisor exited before the session was ready. " \
          "See #{File.join(store.session_dir(name), 'supervisor.log')}."
      end

      # ---- send

      def send_input(args)
        options, rest, error = extract_options(args)
        return Result.failure(error) if error
        return Result.failure(name_error(options[:name])) unless Session::Store.valid_name?(options[:name])

        text = (rest.first == '--' ? rest[1..] : rest).join(' ')
        regex_error = validate_regex(options[:wait_for_regex])
        return Result.failure(regex_error) if regex_error

        exchange(options[:name], send_payload(options, text),
                 action: 'send', screen: options[:screen], options: options)
      end

      def send_payload(options, text)
        {
          op: 'send', text: text,
          settle_ms: options[:settle_ms], timeout_ms: options[:timeout_ms],
          wait_for_regex: options[:wait_for_regex],
          no_wait: options[:no_wait], no_newline: options[:no_newline]
        }.compact
      end

      # The child's state, on every send and read.
      #
      # Only `list` carried it, and the driving loop is send -> read -> send. A
      # child that exited answered `settled: true` with no indication, so a naive
      # loop drove a corpse forever seeing plausible replies each time. Reported
      # from real use by someone who read `settled: true, matched: nil` at 1198ms
      # against a 30s settle window and started drafting a bug that --settle-ms
      # was being ignored — the child had died. Presentation gap, not a data gap.
      def liveness(name)
        meta = store.read_meta(name) || {}
        { state: meta[:state], exit_code: meta[:exit_code] }.compact
      end

      def validate_regex(source)
        return nil if source.nil?

        Regexp.new(source)
        nil
      rescue RegexpError => e
        "Invalid --wait-for-regex value: #{e.message}"
      end

      def exchange(name, payload, action:, screen: false, options: {})
        alive = alive_session(name)
        return alive if alive.is_a?(Result)

        reply = Timeout.timeout(client_ceiling(payload)) do
          Session::Client.new(store.socket_path(name)).request(payload)
        end
        return Result.failure("Session #{name.inspect}: #{reply[:error]}") if reply[:error]

        Result.success({ action: action, name: name }
                         .merge(bounded_output(reply, options))
                         .merge(liveness(name))
                         .merge(screen_after(name, screen)))
      rescue Session::Client::Unavailable => e
        Result.failure("Session #{name.inspect} is not reachable (#{e.message}). It may have exited; " \
                       "run 'rune session list'.")
      rescue Timeout::Error
        Result.failure("Session #{name.inspect} did not answer within its timeout. The supervisor may be " \
                       "wedged; run 'rune session stop --name=#{name}' to recover.")
      end

      # `Client` has no timeout of its own because the supervisor guarantees a
      # reply. That guarantee does not hold when the supervisor is wedged — a
      # blocking pty write is a documented limitation — and without a ceiling the
      # caller then blocks forever, turning a stalled supervisor into a hung
      # agent with no recovery but killing it by hand. The margin is generous so
      # this can never pre-empt a legitimate wait the caller asked for.
      def client_ceiling(payload)
        ((payload[:timeout_ms] || DEFAULT_SEND_TIMEOUT_MS) / 1000.0) + CLIENT_TIMEOUT_MARGIN
      end

      # `rune run` has always returned both an ANSI-stripped `clean_output` and
      # the untouched `raw_output`; sessions returned only the raw text, so
      # every caller driving a full-screen TUI agent had to write its own ANSI
      # stripper before it could read a reply. That asymmetry was a real gap,
      # not a stylistic one — it is the difference between a session being
      # usable from a shell one-liner and needing a helper program.
      def with_clean_output(reply)
        return reply unless reply.key?(:output)

        reply.merge(clean_output: Parsers::TextSanitizer.strip_ansi(reply[:output]))
      end

      # `--max-output` and `--tail` were parsed for every subcommand but applied
      # only by `read`, so `send` accepted both and silently returned everything.
      # That is the wrong one to leave unbounded: `send` is the call an agent
      # makes most, and one turn of a full-screen TUI is megabytes. An agent that
      # asked for a bound and was told `status: ok` had no way to know it did not
      # get one.
      #
      # Bounding happens here rather than in the supervisor because the cap is a
      # presentation choice of this one caller — the transcript, the cursor, and
      # every other attached client must still see the whole stream.
      def bounded_output(reply, options)
        return with_clean_output(reply) unless reply.key?(:output) &&
                                               (options[:max_output_bytes] || options[:tail_lines])

        # Bound the raw text and derive `clean_output` from the bounded result,
        # which is what `read` does. Bounding the two independently would let
        # them describe different windows of the same reply, and leave the
        # `omitted_bytes` count true of only one of them.
        bounded, extra = bound_size(reply[:output].to_s, options)
        reply.merge(output: bounded,
                    clean_output: Parsers::TextSanitizer.strip_ansi(bounded)).merge(extra)
      end

      def alive_session(name)
        return Result.failure(no_such_session(name)) unless store.exist?(name)

        meta = store.read_meta(name)
        return Result.failure(no_such_session(name)) unless meta
        return nil if Session::Store.alive?(meta[:supervisor_pid])

        Result.failure("Session #{name.inspect} is not running (state #{meta[:state]}, " \
                       "exit code #{meta[:exit_code].inspect}).")
      end

      # ---- read

      def read_transcript(args)
        options, _rest, error = extract_options(args)
        return Result.failure(error) if error
        return Result.failure(name_error(options[:name])) unless Session::Store.valid_name?(options[:name])
        return Result.failure(no_such_session(options[:name])) unless store.exist?(options[:name])

        transcript = Session::Transcript.load(store.output_path(options[:name]))
        read_result(options, transcript)
      end

      # Whether the child has produced output recently enough to call it busy,
      # and how long since it last did. `list` already reported this; a caller
      # deciding whether a turn is finished needs it on `read` too, and was
      # otherwise grepping the callee's own rendered UI for a busy marker —
      # presentation, not API, and it breaks when the wording changes.
      #
      # Derived from the transcript's own timestamps rather than asked of the
      # supervisor, so it works identically for a stopped session.
      def busy_fields(options)
        idle = activity(store, options[:name])[:idle_ms]
        return {} unless idle

        { idle_ms: idle, child_busy: idle < Session::Supervisor::DEFAULT_SETTLE_MS }
      end

      def read_result(options, transcript)
        sliced, withheld = withhold_dangling(transcript.from(options[:since]))
        bounded, extra = bound_output(sliced, options, transcript)

        Result.success(read_payload(options, transcript, sliced, bounded, withheld).merge(extra))
      end

      # A read stops at the last complete escape sequence, not at the last byte.
      #
      # The bytes of a sequence still waiting for its terminator are withheld from the reply *and*
      # from the cursor, so the next read starts at the ESC and sees the sequence whole. Without
      # this, both halves of a split sequence are wrong: the fragment survives `strip_ansi` and is
      # delivered as visible text, and the next read from the handed-out cursor sees the remainder
      # headless. Measured on a child that printed `\e[3`, slept, then `1mRED\e[0m` — one read
      # returned `clean_output` `"READY\n\e[3"` and the next returned `"1mRED"` while `screen` in
      # that same reply said `"RED"`.
      #
      # Nothing is lost: the withheld bytes stay in the transcript and are returned once the
      # sequence completes. A child that opens a sequence and never closes it withholds those bytes
      # indefinitely, which is what a terminal does with them too — it shows nothing.
      def withhold_dangling(text)
        dangling = OutputLimiter.dangling_suffix(text)
        return [text, 0] if dangling.empty?

        kept = text.byteslice(0, text.bytesize - dangling.bytesize).to_s
        [kept.force_encoding(text.encoding).scrub, dangling.bytesize]
      end

      def read_payload(options, transcript, sliced, bounded, withheld = 0)
        { action: 'read', name: options[:name], output: bounded,
          clean_output: Parsers::TextSanitizer.strip_ansi(bounded),
          cursor: transcript.cursor - withheld,
          prompt_detected: Session::PromptScanner.prompt_at_end?(sliced) }
          .merge(transcript.dropped.positive? ? { dropped_bytes: transcript.dropped } : {})
          .merge(busy_fields(options))
          .merge(liveness(options[:name]))
          .merge(options[:screen] ? screen_fields(transcript, options[:name]) : {})
      end

      # The screen as it stands once the send has settled. Read from the
      # transcript file in this process rather than asked of the supervisor: a
      # long session would otherwise pay to re-render on the one thread that has
      # to keep pumping the pty.
      def screen_after(name, screen)
        return {} unless screen

        screen_fields(Session::Transcript.load(store.output_path(name)), name)
      end

      # Rendered at the size the child's pty is actually set to, which is not
      # the size it was started at: `attach` resizes the child to the human's
      # terminal, so for the whole time anyone is attached from a window that is
      # not 40x120 a fixed default renders a screen the child never drew. The
      # supervisor records the current winsize in meta on every resize; this
      # reads it back.
      #
      # The size is reported alongside the screen because a caller cannot
      # otherwise tell a real geometry from the fallback, and the numbers alone
      # cannot carry that distinction either: a session attached from a 40-row
      # terminal records exactly the fallback's own 40x120.
      #
      # `screen_size_recorded` is the field that can. False means the size shown
      # is the documented default, for one of three reasons — nobody has resized
      # this child (where the default is not a guess: it is what the supervisor
      # set the pty to), the session directory predates rune recording a size at
      # all, or meta held a size the renderer refused as unusable.
      def screen_fields(transcript, name)
        rows, columns, recorded = window_size(name)
        { screen: transcript.screen(rows: rows, columns: columns),
          screen_rows: rows, screen_cols: columns, screen_size_recorded: recorded }
      end

      # The child's last recorded winsize, resolved through the renderer so an
      # absent one (an old session directory) or a nonsensical one (hand-edited
      # meta, a pty whose size was never set) becomes the documented default
      # rather than a crash.
      #
      # "Recorded" is decided by comparing the resolved size against what meta
      # actually held, not by whether the keys are present, so a value that was
      # clamped or discarded on the way through is reported as the default it
      # became.
      def window_size(name)
        meta = store.read_meta(name) || {}
        rows, columns = Parsers::ScreenRenderer.dimensions(meta[:rows], meta[:cols])
        # A size the supervisor had to reduce is not the child's geometry, so it
        # is not "recorded" either — the spec said as much before the code did.
        recorded = rows == meta[:rows] && columns == meta[:cols] && !meta[:size_reduced]
        [rows, columns, recorded]
      end

      def bound_output(text, options, transcript = nil)
        text, grep_extra = filter(text, options, transcript)
        bounded, extra = bound_size(text, options)
        [bounded, grep_extra.merge(extra)]
      end

      # Finding one answer inside a long transcript otherwise means pulling most
      # of it: a driven agent's transcript reached 379KB in a day's work, and
      # neither `--since` nor `--tail` helps when what you want is in the middle.
      def filter(text, options, transcript)
        return [text, {}] unless options[:grep] && transcript

        pattern, reason = compile_grep(options[:grep])
        return [+'', grep_failure(options[:grep], reason)] unless pattern

        # The sliced text, not the whole transcript: `--since` had no effect on a grepped read
        # because this discarded the slice it was handed.
        filtered, matches = Session::Transcript.grep_text(text, pattern, context: options[:context_lines].to_i)
        [filtered, { grep: options[:grep], grep_matches: matches }]
      end

      # A filter that will not compile selected nothing, so nothing is what the
      # read returns.
      #
      # It used to return the *entire* transcript: `--grep='[unclosed'` came back
      # `status: ok` carrying every byte — the exact opposite of the same read
      # with a valid pattern that matches nothing, which returns zero. A caller
      # that did not read `grep_error` therefore saw every line as though it had
      # matched, at the maximum possible cost. A filter that cannot run should
      # fail closed.
      #
      # The read itself still succeeds, which is deliberate and is the whole
      # reason `grep_error` exists: `read` also carries `cursor`, `dropped_bytes`,
      # `prompt_detected`, `idle_ms`/`child_busy` and optionally `screen`, none of
      # which the pattern has any bearing on, and a `Result.failure` would throw
      # all of it away — including the cursor the caller needs to make progress —
      # and would leave `grep_error` with no envelope to travel in. (`send`
      # rejects a bad `--wait-for-regex` outright, and should: there the pattern
      # decides *when to return*, so proceeding would mean writing the input and
      # then waiting out the full timeout.)
      #
      # `grep_matches` is deliberately absent rather than `0`: nothing was
      # searched, and a caller must be able to tell that from a search that found
      # nothing.
      def grep_failure(source, reason)
        { grep: source, grep_error: "invalid --grep pattern: #{reason}; returned no output" }
      end

      # Returns `[pattern, nil]`, or `[nil, reason]` for a pattern that will not
      # compile. The reason is Ruby's own message, which both quotes the pattern
      # and says what is wrong with it (`premature end of char-class: /[unclosed/`);
      # the old message named the pattern and stopped there, so a caller was told
      # its filter was bad but not why.
      def compile_grep(source)
        [Regexp.new(source), nil]
      rescue RegexpError => e
        [nil, e.message.lines.first.to_s.strip]
      end

      def bound_size(text, options)
        if options[:max_output_bytes]
          bounded, omitted = OutputLimiter.truncate_middle(text, options[:max_output_bytes])
          return [bounded, omitted.positive? ? { truncated: true, omitted_bytes: omitted } : {}]
        end
        if options[:tail_lines]
          bounded, omitted = OutputLimiter.tail_lines(text, options[:tail_lines])
          return [bounded, omitted.positive? ? { truncated: true, omitted_lines: omitted } : {}]
        end

        [text, {}]
      end

      # ---- attach

      # Hands a live session to a human terminal. `start` and `send` are the
      # agent-facing half of the feature; this is the half that makes a named
      # session something you can come back to yourself — take the wheel, then
      # detach and leave the agent running exactly where it was.
      def attach(args)
        options, _rest, error = extract_options(args)
        return Result.failure(error) if error
        return Result.failure(name_error(options[:name])) unless Session::Store.valid_name?(options[:name])

        alive = alive_session(options[:name])
        return alive if alive.is_a?(Result)
        unless $stdin.tty?
          return Result.failure('rune session attach requires a real terminal (stdin is not a TTY). ' \
                                'Use `rune session send`/`read` for non-interactive access.')
        end

        Session::Attachment.new(store.socket_path(options[:name])).run
      end

      # ---- list

      def list(args)
        options, _rest, error = extract_options(args)
        return Result.failure(error) if error
        return list_archived if options[:archived]
        return list_all_projects if options[:all_projects]

        Result.success({ action: 'list', project: store.project,
                         sessions: with_orphans(store.names.map { |name| describe(name) }, store) })
      end

      def list_archived
        Result.success({ action: 'list', project: store.project, archived: true,
                         sessions: store.archived_names.map { |entry| { name: entry, state: 'archived' } } })
      end

      # Sessions are project-scoped by design, so seeing everything has to be
      # asked for explicitly rather than being the default.
      def list_all_projects
        sessions = Session::Store.projects(store.home).flat_map do |project|
          scoped = Session::Store.new(home: store.home, project: project)
          described = scoped.names.map { |name| describe(name, scoped).merge(project: project) }
          with_orphans(described, scoped)
        end
        Result.success({ action: 'list', all_projects: true, sessions: sessions })
      end

      # ---- orphaned children
      #
      # A supervisor killed with SIGKILL leaves its child running, reparented to
      # pid 1 and still holding the pty. Nothing in rune owns that process any
      # more, and nothing used to say so: `list` showed the session `dead` and
      # `archive` filed it away, both without a word about the pid still burning
      # CPU behind them.
      #
      # This reports and never blocks. An earlier attempt refused the archive and
      # sent the caller to `rune session stop`, which kills the recorded child's
      # whole process group — so the moment its liveness test was wrong about a
      # recycled pid, the remedy killed a stranger. It was wrong often: that test
      # asked the process *group*, on the premise that a recycled pid sits in its
      # parent's group, and on this machine 87.9% of live processes lead their own
      # group. Two runs of it killed unrelated live groups (pids 92948 and 80847).
      # Reporting cannot do that, so the accuracy question stops being a safety
      # question and becomes an honesty one.
      #
      # The state field is deliberately not consulted. The refusal skipped any
      # session recorded `exited`/`stopped`/`failed`, which is exactly where the
      # bug lives: `Supervisor#cleanup` used to write `state: 'exited'` before it
      # terminated the child, so a supervisor dying in that window left a
      # concluded record next to a live process and the check waved it through.
      # `state` is a claim by a process that is now dead; the pair below is
      # evidence.
      def with_orphans(described, scoped)
        orphans = orphaned_pids(described.map { |entry| entry[:name] }, scoped)
        return described if orphans.empty?

        described.map do |entry|
          pid = orphans[entry[:name]]
          pid ? entry.merge(orphaned_child_pid: pid) : entry
        end
      end

      # Sessions whose supervisor is gone but whose recorded child is provably
      # still the same process, still running. Batched into one `ps` for the
      # whole listing, and skipped entirely when nothing qualifies, because
      # `list` runs while several agents are working and has to stay cheap.
      def orphaned_pids(names, scoped)
        candidates = names.filter_map { |name| orphan_candidate(name, scoped) }
        return {} if candidates.empty?

        live = Session::Store.process_start_times(candidates.map { |candidate| candidate[1] })
        candidates.each_with_object({}) do |(name, pid, started), found|
          found[name] = pid if live[pid] == started
        end
      end

      # `[name, pid, recorded start time]`, or nil when the question cannot be
      # asked soundly. A live supervisor disqualifies the session because its
      # child is *supposed* to be running — "orphan" means nothing owns it. A
      # missing `child_started_at` disqualifies it because that is a session
      # started before this field existed, or one whose supervisor died in the
      # window before it was written: the honest answer there is silence, not a
      # guess from the bare pid.
      def orphan_candidate(name, scoped)
        meta = scoped.read_meta(name) || {}
        pid = Session::Store.positive_pid(meta[:child_pid])
        started = meta[:child_started_at]
        return nil if pid.nil? || started.nil? || started.to_s.empty?
        return nil if Session::Store.alive?(meta[:supervisor_pid])

        [name, pid, started]
      end

      # State is always recomputed from real process liveness. A supervisor
      # killed with SIGKILL never updates meta.json, so a recorded "running"
      # is routinely stale and must never be reported as-is.
      def describe(name, scoped = store)
        meta = scoped.read_meta(name) || {}
        alive = Session::Store.alive?(meta[:supervisor_pid])
        # "dead" is reserved for a supervisor that vanished without recording
        # why — the stale-state case. A session that exited on its own or was
        # stopped deliberately reports that instead, so the two are
        # distinguishable rather than collapsed into one alarming word.
        state = if alive then 'running'
                elsif %w[exited stopped].include?(meta[:state]) then meta[:state]
                else 'dead'
                end
        { name: name, state: state, command: meta[:command], child_pid: meta[:child_pid],
          supervisor_pid: meta[:supervisor_pid], exit_code: meta[:exit_code],
          started_at: meta[:started_at] }.merge(activity(scoped, name))
      end

      # "Is it working or is it stuck, and what was it last doing" is the whole
      # question when several agents are running at once, and the transcript
      # already answers it — every event carries a timestamp. Read from the tail
      # rather than the whole file: a driven TUI agent's transcript reaches
      # megabytes quickly and `list` must stay cheap.
      def activity(scoped, name)
        path = scoped.output_path(name)
        return {} unless File.exist?(path)

        events = tail_events(path)
        # Summarised from the reassembled tail rather than from the last event on its own. A pty
        # read boundary is not a line boundary and not a sequence boundary: a child that printed
        # `\e[3` and then `1mRED` puts those in two events, and an event-at-a-time summary strips
        # nothing from either, so `list` reported the last line as `1mRED` where the child had
        # displayed `RED`. Joined first, the sequence is whole and strips correctly.
        text = events.select { |event| event['event'] == 'output' }.map { |event| event['text'].to_s }.join
        stamp = events.filter_map { |event| event['ts'] }.last
        summary = summarize(withhold_dangling(text).first)
        { idle_ms: stamp ? ((Time.now.to_f - stamp) * 1000).round : nil,
          last_line: summary.empty? ? nil : summary }.compact
      end

      def tail_events(path, bytes: ACTIVITY_TAIL_BYTES)
        size = File.size(path)
        raw = File.open(path, 'rb') do |file|
          file.seek([size - bytes, 0].max)
          file.read.to_s
        end
        lines = raw.scrub.lines
        # A seek into the middle of the file usually lands mid-line; that first
        # fragment is not parseable JSON and is not ours to interpret.
        lines.shift if size > bytes && lines.size > 1
        lines.filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      # One readable line: the last thing the agent actually printed, stripped
      # of the escape traffic a full-screen TUI generates.
      def summarize(text)
        cleaned = Parsers::TextSanitizer.strip_ansi(text.to_s)
        line = cleaned.lines.reverse_each.find { |candidate| candidate.strip != '' }
        line.to_s.strip[0, ACTIVITY_LINE_LIMIT]
      end

      # ---- stop

      def stop(args)
        options, _rest, error = extract_options(args)
        return Result.failure(error) if error
        return Result.failure(name_error(options[:name])) unless Session::Store.valid_name?(options[:name])

        name = options[:name]
        return Result.failure(no_such_session(name)) unless store.exist?(name)

        meta = store.read_meta(name) || {}
        graceful_stop(name)
        # The graceful path has to be given time to actually happen. Acking the
        # stop only sets a flag; the supervisor tears down on its next tick, and
        # SIGKILLing it in between meant the graceful path never once ran. The
        # cost was not theoretical: an in-flight send's caller got "supervisor
        # closed the connection without replying" instead of the output it had
        # been waiting for, because `resolve_orphaned_pending` never executed —
        # and the control socket was left on disk because `cleanup` did not
        # either. `kill_remaining` is still called, and no-ops on a pid that has
        # already gone.
        await_exit(meta[:supervisor_pid])
        kill_remaining(meta)
        # SIGKILL is asynchronous, so without waiting `stop` returned while the
        # processes were still dying and the very next command saw the session
        # as running — `archive` straight after `stop` failed on exactly this.
        # A caller should be able to treat `stop` as done when it returns.
        await_death(meta)
        store.update_meta(name, state: 'stopped', stopped_at: Time.now.to_f)
        Result.success({ action: 'stop', name: name, state: 'stopped' })
      end

      # Bounded on purpose. `Client` deliberately has no timeout because the
      # supervisor guarantees a reply — but `stop` is the documented recovery
      # path for a session that is *already* misbehaving, so it cannot depend on
      # that guarantee holding. Without the bound, a wedged supervisor made
      # `rune session stop` block here forever and never reach kill_remaining,
      # leaving the very process the user was trying to kill running.
      def graceful_stop(name)
        Timeout.timeout(GRACEFUL_STOP_TIMEOUT) do
          Session::Client.new(store.socket_path(name)).request(op: 'stop')
        end
      rescue Session::Client::Unavailable, Timeout::Error
        nil
      end

      # Waits for a cooperative shutdown to complete, bounded so a wedged
      # supervisor still gets force-killed rather than holding `stop` open.
      def await_exit(pid)
        return unless pid

        deadline = monotonic + GRACEFUL_STOP_TIMEOUT
        sleep 0.02 while Session::Store.alive?(pid) && monotonic < deadline
      end

      def await_death(meta)
        pids = [meta[:child_pid], meta[:supervisor_pid]].compact
        deadline = monotonic + DEATH_TIMEOUT
        sleep 0.02 while pids.any? { |pid| Session::Store.alive?(pid) } && monotonic < deadline
      end

      # Idempotent by construction: every kill tolerates an already-dead pid,
      # so stopping a stopped session succeeds rather than erroring.
      # The child is signalled by process group so its own workers go too; the
      # supervisor is signalled directly, since group-killing it could reach
      # this process. Every kill tolerates an already-dead pid, which is what
      # makes `stop` idempotent.
      def kill_remaining(meta)
        kill_process_group(meta[:child_pid])
        kill_pid(meta[:supervisor_pid])
      end

      # Not guarded on the leader being alive. A process group outlives its
      # leader: an agent CLI whose wrapper exits while its workers keep running
      # leaves a live group behind a dead pid, and checking the leader first
      # skipped the kill and orphaned exactly those workers. Signalling a group
      # with no members raises ESRCH, which the rescue already handles.
      def kill_process_group(pid)
        return unless pid

        Process.kill('KILL', -Integer(pid))
      rescue Errno::ESRCH, Errno::EPERM, TypeError, ArgumentError
        kill_pid(pid)
      end

      def kill_pid(pid)
        return unless pid && Session::Store.alive?(pid)

        Process.kill('KILL', Integer(pid))
      rescue Errno::ESRCH, Errno::EPERM, TypeError, ArgumentError
        nil
      end

      # ---- hidden supervisor entry point

      def supervise(args)
        options, rest, error = extract_options(args)
        return Result.failure(error) if error

        # `_supervise` is internal but still dispatchable, and `Store` derives
        # directory paths straight from the name, so skipping the guard `start`
        # applies would let `--name=../../x` write session state outside
        # RUNE_HOME. Defence in depth, not a reachable exploit today.
        return Result.failure(name_error(options[:name])) unless Session::Store.valid_name?(options[:name])

        command = rest.first == '--' ? rest[1..] : rest
        # The project is passed explicitly rather than re-derived: the
        # supervisor is detached and must not depend on inheriting a cwd.
        Session::Supervisor.run(name: options[:name], command: command,
                                home: options[:home], project: options[:project])
        Result.success({ action: 'supervise', name: options[:name] })
      end

      # ---- archive

      # Moves a finished session out of the live namespace. Without this a name
      # stays taken by something long dead, and `list` mixes history in with
      # what is actually running.
      def archive_session(args)
        options, _rest, error = extract_options(args)
        return Result.failure(error) if error

        rejection = archive_rejection(options[:name])
        return rejection if rejection

        # Read before the move, because the move is what makes the pid
        # unreachable: once the directory is out of the live namespace, `list`
        # will not show the session and `stop` answers "no such session", so this
        # reply is the last place the number appears. Reported rather than
        # refused — see `with_orphans` for why refusing was worse than the gap it
        # covered.
        orphan = orphaned_pids([options[:name]], store)[options[:name]]
        target = store.archive(options[:name], stamp: Time.now.strftime('%Y%m%d-%H%M%S'))
        Result.success({ action: 'archive', name: options[:name],
                         archived_to: File.basename(target),
                         orphaned_child_pid: orphan }.compact)
      end

      def archive_rejection(name)
        return Result.failure(name_error(name)) unless Session::Store.valid_name?(name)
        return Result.failure(no_such_session(name)) unless store.exist?(name)

        supervisor = (store.read_meta(name) || {})[:supervisor_pid]
        return Result.failure(still_running(name)) if Session::Store.alive?(supervisor)

        nil
      end

      def still_running(name)
        "Session #{name.inspect} is still running. Stop it first: rune session stop --name=#{name}"
      end

      # ---- shared option parsing

      # Same separator discipline as `rune run`: rune's flags are recognized
      # only before the first `--`, so a wrapped command's identically named
      # flags are passed through untouched.
      #
      # Both `--name=x` and `--name x` are accepted. The space-separated form
      # is not sugar here: `--name` is the flag nearly every invocation passes,
      # and in the `=`-only parsing this started with, `--name foo -- cmd`
      # silently swallowed `foo` into the wrapped command's argv and then failed
      # with "a session name is required" — a confusing error a long way from
      # its cause.
      # `operand_owns_flags` is true only for `start`, whose operand is a
      # program followed by that program's own argv — `start --name=x claude
      # --resume` must keep working, so a flag after the program name is the
      # child's business.
      #
      # Everywhere else it is false, and that is the fix: `send` takes literal
      # text, and rune *consumes* a correctly-spelled flag after it
      # (`send 'echo hi' --settle-ms 600` really does have its flag eaten) while
      # a mistyped one was typed at the child under `status: ok`. Permuting for
      # consumption and not for validation was the inconsistency.
      def extract_options(args, operand_owns_flags: false)
        separator_index = args.index('--')
        head = separator_index ? args[0...separator_index] : args
        tail = separator_index ? args[separator_index..] : []

        options, rest, error = scan_flags(head, operand_owns_flags: operand_owns_flags)
        error ||= conflicting_bounds(options)
        [options, rest + tail, error]
      end

      # `rune run` has always refused this pair; sessions accepted both and
      # applied whichever `bound_size` checked first, so a caller that asked for
      # `--tail` alongside `--max-output` was told `status: ok` and quietly given
      # the other one. Same message as `run`, because it is the same mistake.
      def conflicting_bounds(options)
        return nil unless options[:max_output_bytes] && options[:tail_lines]

        'Cannot combine --max-output and --tail; use one or the other.'
      end

      def flag_to_validate?(token, rest, operand_owns_flags)
        return false unless self.class.flag_shaped?(token)

        operand_owns_flags ? rest.empty? : true
      end

      def scan_flags(head, operand_owns_flags: false)
        options = {}
        error = nil
        rest = []
        index = 0
        while index < head.length
          consumed, message = consume_flag(head, index, options)
          error ||= message
          if consumed.zero?
            # Validated wherever a flag would have been CONSUMED, not only
            # before the first operand. `consume_flag` is tried at every index,
            # so `send 'echo hi' --settle-ms 600` really does have its flag
            # eaten by rune — while `send 'echo hi' --settle_ms 600` was typed
            # at the child with status: ok. Permuting for consumption and not
            # for validation is the inconsistency; this closes it.
            error ||= unknown_flag_error(head[index]) if flag_to_validate?(head[index], rest, operand_owns_flags)
            rest << head[index]
          end
          index += consumed.zero? ? 1 : consumed
        end

        [options, rest, error]
      end

      # `rune session frobnicate` has always been rejected, but a mistyped
      # *flag* was not: `send --settle_ms 500 'echo HELLO'` (underscore for dash)
      # matched nothing, so the flag, its value and the input were joined with
      # spaces and typed at the child, which answered `status: ok`. Against
      # `cat` that echoes back nonsense; against an agent CLI it is a garbage
      # prompt to a paid model, and against a confirmation dialog it is an
      # answer nobody meant to give.
      #
      # Two limits keep this from rejecting anything that works today. Nothing
      # after the first `--` is examined, so the documented passthrough is
      # untouched: `send --name=NAME -- --settle_ms` still types `--settle_ms`
      # at the child, and that is what the error points at. And nothing after
      # the first operand is examined either, which is the getopt convention and
      # is what `rune session start --name=x claude --resume` needs — past the
      # program name every `--flag` belongs to the child, not to rune. The same
      # rule keeps `send --name=x git log --oneline` typing what it says.
      def unknown_flag_error(token)
        return nil unless self.class.flag_shaped?(token)

        name = token.split('=', 2).first
        "Unknown option: #{name}.#{suggestion(name)} " \
          'Flags are recognized only before a `--` separator; to send it to the child as literal ' \
          "input, put it after one: rune session <subcommand> --name=NAME -- #{name}"
      end

      # Only the dash-for-underscore confusion, which is the mistake actually
      # observed and the one an exact-match check can call with certainty. A
      # fuzzy matcher would start guessing, and a wrong guess in an error message
      # is worse than none.
      def suggestion(name)
        candidate = name.tr('_', '-')
        KNOWN_FLAGS.include?(candidate) && candidate != name ? " Did you mean #{candidate}?" : ''
      end

      # Returns [tokens_consumed, error]. Zero means "not one of our flags".
      def consume_flag(head, index, options)
        boolean = BOOLEAN_FLAGS[head[index]]
        if boolean
          options[boolean] = true
          return [1, nil]
        end

        consume_value_flag(head, index, options)
      end

      def consume_value_flag(head, index, options)
        arg = head[index]
        VALUE_FLAGS.each do |key, (pattern, kind)|
          inline = arg.match(pattern)
          return assign(options, key, kind, inline[1], 1) if inline
          next unless separate_form?(arg, key)
          return [2, "#{flag_name(key)} requires a value."] if head[index + 1].nil?

          return assign(options, key, kind, head[index + 1], 2)
        end
        [0, nil]
      end

      def assign(options, key, kind, raw, consumed)
        value, message = coerce(raw, kind, key)
        options[key] = value unless message
        [consumed, message]
      end

      def separate_form?(arg, key) = arg == flag_name(key) || arg == "--#{dashed(key)}"

      def dashed(key) = key.to_s.tr('_', '-')

      # Internal keys whose user-facing flag is not their name with dashes.
      # Every one of these has to be listed: a missing entry made the separate
      # form of the flag unrecognised, so `--context 3` was silently swallowed
      # and typed at nothing while `--context=3` worked — and it made error
      # messages name flags that do not exist, such as
      # `Invalid --tail-lines value`.
      def flag_alias(key) = ALIASES[key]

      # What to call a flag when speaking to the person who typed it.
      def flag_name(key) = ALIASES[key] || "--#{dashed(key)}"

      def coerce(raw, kind, key)
        case kind
        when :string then raw.empty? ? [nil, "#{flag_name(key)} requires a value."] : [raw, nil]
        when :positive_int then integer(raw, key, positive: true)
        else integer(raw, key, positive: false)
        end
      end

      def integer(raw, key, positive:)
        return [raw.to_i, nil] if raw.match?(/\A\d+\z/) && (!positive || raw.to_i.positive?)

        [nil, "Invalid #{flag_name(key)} value: #{raw.inspect}. " \
              "Must be a #{positive ? 'positive' : 'non-negative'} integer."]
      end

      def name_error(name)
        return 'A session name is required: --name=NAME.' if name.nil? || name.empty?

        "Invalid session name #{name.inspect}. Use letters, digits, '.', '_' or '-' (max 64 chars), " \
          'starting with a letter or digit.'
      end

      # Says where the session actually is, when it is somewhere.
      #
      # The old message was confidently wrong and its remedy confirmed the error: a session started
      # in one directory and read from another got `No such session: "s3". Run 'rune session list'.`
      # — and `list`, scoped to the caller's own project, returned nothing, which reads as proof
      # the session died. Two people who had read the guide's warning about directory scoping hit
      # this anyway, one of them mid-way through debugging the child instead.
      #
      # rune already knows the answer: `--all-projects` finds it. An error that can name the project
      # should name it rather than send the reader to a command that shows them nothing.
      def no_such_session(name)
        elsewhere = projects_holding(name)
        return "No such session: #{name.inspect}. Run 'rune session list'." if elsewhere.empty?

        "No session #{name.inspect} in this project (#{store.project}), but it exists in " \
          "#{elsewhere.length == 1 ? elsewhere.first.inspect : elsewhere.map(&:inspect).join(', ')}. " \
          'A project is the working directory, so `cd` there, or run `rune session list --all-projects`.'
      end

      # Cheap: a directory listing per project, no transcripts opened. Rescued because a
      # best-effort hint must never turn a clear error into a crash.
      def projects_holding(name)
        Session::Store.projects(store.home).reject { |project| project == store.project }.select do |project|
          Session::Store.new(home: store.home, project: project).exist?(name)
        end
      rescue StandardError
        []
      end

      def render_list(data, io)
        return io.puts('No sessions.') if data[:sessions].empty?

        data[:sessions].each do |session|
          icon = session[:state] == 'running' ? "\e[32m●\e[0m" : "\e[90m○\e[0m"
          scope = session[:project] ? "\e[90m[#{session[:project]}]\e[0m " : ''
          io.puts "#{icon} #{scope}\e[1m#{session[:name]}\e[0m  #{session[:state]}#{idle_suffix(session)}  " \
                  "#{Array(session[:command]).join(' ')}"
          io.puts "    \e[90m#{session[:last_line]}\e[0m" if session[:last_line]
          render_orphan(session, io)
        end
      end

      def render_orphan(session, io)
        return unless session[:orphaned_child_pid]

        io.puts "    \e[33m! child pid #{session[:orphaned_child_pid]} is still running with no supervisor\e[0m"
      end

      # Idle time is the fastest read on "is this one stuck": a running agent
      # that has printed nothing for minutes is the thing you want to notice.
      def idle_suffix(session)
        return '' unless session[:idle_ms]

        seconds = session[:idle_ms] / 1000
        return "  \e[90midle #{seconds}s\e[0m" if seconds < 90

        "  \e[90midle #{(seconds / 60.0).round}m\e[0m"
      end

      def store = @store ||= Session::Store.new(project: @project_override)

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    # rubocop:enable Metrics/ClassLength
  end
end
