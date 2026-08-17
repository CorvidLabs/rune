# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'digest'

module Rune
  module Session
    # rubocop:disable Metrics/ClassLength -- path derivation, project scoping, archiving and the
    # owner-only write helpers are all one concern (where a session's bytes live) and splitting
    # them across classes would separate the paths from the permissions that must accompany them.
    #
    # On-disk state for persistent sessions. Deliberately dumb: it knows where
    # a session's files live and how to read/write them with the right modes,
    # and nothing about PTYs or protocol. Every path is derived from a single
    # `home` so the whole tree can be redirected at a temp dir in tests — no
    # spec ever touches a real user's ~/.rune.
    class Store
      DEFAULT_DIR_NAME = '.rune'
      # Owner-only, matching the precedent already set for `rune watch`'s
      # default event log: a session transcript carries whatever the driven
      # agent printed, which routinely includes source and credentials.
      DIR_MODE = 0o700
      FILE_MODE = 0o600

      # A session name becomes a directory name, so it must not be able to
      # escape the sessions dir or collide with the control files inside it.
      NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/

      # Auto-generated names pair the tool being driven with a distinct word,
      # e.g. `grok-amber`. The tool half is what makes a name readable at a
      # glance; the word half is what stops "the grok session" from being
      # ambiguous the moment there are two of them.
      CODENAMES = %w[
        amber basalt cedar dusk ember flint glade harbor indigo jade kestrel
        larch mesa nimbus onyx pike quartz reef slate tundra umber vale willow
        yarrow zephyr
      ].freeze

      attr_reader :home, :project

      def initialize(home: nil, project: nil)
        @home = home || self.class.default_home
        @project = project || self.class.project_slug
      end

      # Sessions are scoped to a project, so `reviewer` in one repo is a
      # different session from `reviewer` in another and neither can be reached
      # by accident from the wrong directory. The slug keeps the readable
      # basename but appends a digest of the absolute path, because two
      # checkouts are very often both called the same thing.
      def self.project_slug(path = Dir.pwd)
        root = project_root(path)
        base = File.basename(root).downcase.gsub(/[^a-z0-9]+/, '-').delete_prefix('-')
        base = 'project' unless base.match?(/\A[a-z0-9]/)
        "#{base[0, 32]}-#{Digest::SHA256.hexdigest(root)[0, 8]}"
      end

      # A git working tree is the natural project boundary; outside one, the
      # directory itself is. Walked directly rather than shelling out to git so
      # this stays stdlib-only and cheap.
      def self.project_root(path = Dir.pwd)
        current = canonical(path)
        loop do
          return current if File.exist?(File.join(current, '.git'))

          parent = File.dirname(current)
          return canonical(path) if parent == current

          current = parent
        end
      end

      # Symlinks must not fork a project's identity: /tmp and /private/tmp are
      # the same directory, and without resolving them the same working tree
      # reached by two paths would get two separate session namespaces.
      def self.canonical(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end

      def self.projects(home)
        root = File.join(home, 'projects')
        return [] unless File.directory?(root)

        Dir.children(root).select { |child| File.directory?(File.join(root, child)) }.sort
      end

      # RUNE_HOME is rune's first environment variable and first persisted
      # state. An empty/whitespace value is treated as unset rather than as a
      # request to write to the current directory.
      def self.default_home
        configured = ENV.fetch('RUNE_HOME', nil)
        return configured if configured && !configured.strip.empty?

        File.join(Dir.home, DEFAULT_DIR_NAME)
      end

      def self.valid_name?(name)
        !name.nil? && NAME_PATTERN.match?(name)
      end

      # Liveness is always answered by asking the OS, never by trusting a
      # recorded state field — a supervisor killed with SIGKILL never gets to
      # update meta.json, so a stale "running" is the expected case, not a
      # rare one. EPERM means the pid exists but belongs to someone else, which
      # is still "alive" for our purposes.
      def self.alive?(pid)
        pid = Integer(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, TypeError, ArgumentError
        false
      rescue Errno::EPERM
        true
      end

      # Start times for the pids that still exist, keyed by pid. Pids that have
      # gone are simply absent — `ps` omits them and exits non-zero, which is why
      # the status is not consulted.
      #
      # `alive?` cannot answer "is this still *my* process": a pid is reused, and
      # the pair (pid, start time) is the only identity the OS offers that
      # outlives the parent which spawned it. Asking the process *group* instead
      # is not a substitute and was measured to be actively wrong — on this
      # machine 1_222 of 1_390 live processes (87.9%) lead their own group, and
      # 130 of the 200 most recently allocated pids (65.0%), so a group question
      # answers "alive" for a stranger about as often as a bare pid does.
      #
      # LC_ALL=C is not decoration: `lstart` is formatted through the locale, and
      # the same process reads `Fri Aug 14 13:41:13 2026` under C and
      # `ven. 14 août 13:41:13 2026` under fr_FR. The recorder and the comparer
      # are different processes with different environments, so without pinning
      # the locale a match would depend on them happening to agree.
      def self.process_start_times(pids)
        wanted = Array(pids).filter_map { |pid| positive_pid(pid) }.uniq
        return {} if wanted.empty?

        out = IO.popen([{ 'LC_ALL' => 'C' }, 'ps', '-o', 'pid=,lstart=', '-p', wanted.join(','),
                        { err: File::NULL }], &:read)
        parse_start_times(out)
      rescue SystemCallError, IOError, NotImplementedError
        {}
      end

      def self.process_start_time(pid) = process_start_times([pid])[positive_pid(pid)]

      def self.parse_start_times(output)
        output.to_s.each_line.with_object({}) do |line, map|
          pid, started = line.strip.split(/\s+/, 2)
          next if started.nil? || started.empty?

          key = positive_pid(pid)
          map[key] = started if key
        end
      end

      def self.positive_pid(value)
        pid = Integer(value)
        pid.positive? ? pid : nil
      rescue TypeError, ArgumentError
        nil
      end

      # sockaddr_un caps a Unix socket path at 104 bytes on macOS / 108 on
      # Linux — short enough that an ordinary deep RUNE_HOME (or any
      # Dir.mktmpdir under a long temp root, which is every test) blows it.
      # Binding/connecting from inside the session directory makes the path a
      # bare "control.sock" regardless of how deep the directory itself is.
      #
      # Dir.chdir is process-global, so callers must keep the block to just the
      # bind/connect: the supervisor binds before spawning its child, so the
      # child never inherits the temporary cwd.
      SOCKET_PATH_LIMIT = 100
      # A session's transcript is append-only and a driven agent is chatty, so
      # without a ceiling the file grows for as long as the session lives: a
      # 150-second run at 500KB/s left 80MB behind, and nothing ever removed it.
      # `archive` moves the directory rather than pruning it, so the cost is
      # permanent. Rotating keeps the recent tail, which is what `--since` and
      # an attach backlog actually reach for.
      MAX_LOG_BYTES = 32 * 1024 * 1024
      LOG_KEEP_BYTES = 8 * 1024 * 1024
      # The two bytes `whole_record?` decides on. Compared as bytes rather than
      # characters because the transcript is read in binary mode.
      NEWLINE_BYTE = 0x0A
      CLOSE_BRACE_BYTE = 0x7D

      def self.with_bindable_path(path)
        return yield(path) if path.bytesize < SOCKET_PATH_LIMIT

        Dir.chdir(File.dirname(path)) { yield(File.basename(path)) }
      end

      def project_dir = File.join(@home, 'projects', @project)
      def sessions_dir = File.join(project_dir, 'sessions')
      def archive_dir = File.join(project_dir, 'archive')
      def session_dir(name) = File.join(sessions_dir, name)
      def meta_path(name) = File.join(session_dir(name), 'meta.json')
      def output_path(name) = File.join(session_dir(name), 'output.ndjson')
      def socket_path(name) = File.join(session_dir(name), 'control.sock')
      def lock_path(name) = File.join(session_dir(name), 'start.lock')

      # Serialises `start` for one session name. The conflict check and the
      # recording of a supervisor pid are otherwise a check-then-act pair: two
      # concurrent starts could both see the name as free, and the loser would
      # unlink the winner's socket and orphan a live child. The lock file is
      # never deleted — removing it is what reintroduces the race.
      def with_start_lock(name)
        FileUtils.mkdir_p(session_dir(name))
        File.open(lock_path(name), File::RDWR | File::CREAT, FILE_MODE) do |lock|
          return :busy unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          begin
            yield
          ensure
            lock.flock(File::LOCK_UN)
          end
        end
      end

      def exist?(name) = File.directory?(session_dir(name))

      # Picks an unused `<tool>-<word>` name for a command. Naming every session
      # — rather than leaving `--name` mandatory — means an agent can spin one up
      # without inventing an identifier, and every session still has one.
      def generate_name(command)
        base = name_base(command)
        CODENAMES.shuffle.each do |word|
          candidate = "#{base}-#{word}"
          return candidate unless exist?(candidate)
        end
        # Exhausted the word list for this tool; fall back to a counter.
        suffix = 2
        suffix += 1 while exist?("#{base}-#{suffix}")
        "#{base}-#{suffix}"
      end

      def names
        return [] unless File.directory?(sessions_dir)

        Dir.children(sessions_dir).select { |child| File.directory?(File.join(sessions_dir, child)) }.sort
      end

      def create(name)
        dir = session_dir(name)
        FileUtils.mkdir_p(dir)
        # Every component, not just the leaf. mkdir_p's :mode applies only to
        # directories it actually creates and is masked by umask, so `home`,
        # `projects/`, `projects/<slug>/` and `sessions/` were left at 0755 —
        # letting any local user list which tools are being driven and under
        # what names, even though the transcripts themselves were protected.
        [dir, File.dirname(dir), project_dir, File.join(@home, 'projects'), @home].uniq.each do |path|
          File.chmod(DIR_MODE, path)
        rescue SystemCallError
          next
        end
        dir
      end

      def remove(name) = FileUtils.rm_rf(session_dir(name))

      # Moves a finished session out of the live namespace, so its name is free
      # again and it can never be mistaken for something still running. The
      # timestamp suffix keeps successive archives of the same name distinct.
      def archive(name, stamp:)
        FileUtils.mkdir_p(archive_dir)
        File.chmod(DIR_MODE, archive_dir)
        target = File.join(archive_dir, "#{stamp}-#{name}")
        FileUtils.mv(session_dir(name), target)
        target
      end

      def archived_names
        return [] unless File.directory?(archive_dir)

        Dir.children(archive_dir).select { |child| File.directory?(File.join(archive_dir, child)) }.sort
      end

      # Clears a session's transcript so a reused name starts a fresh lifetime
      # whose byte offsets match the new supervisor's cursors.
      def reset_transcript(name) = FileUtils.rm_f(output_path(name))

      # Written to a temp file and renamed, never truncated in place.
      #
      # Every other rune process answers "does this session exist, and is it
      # alive?" by reading this file, so any instant where it is short or empty
      # is an instant where `send` says "No such session", `list` reports
      # `state: dead`, and `read --screen` loses the recorded geometry and falls
      # back to the default. That used to be rare because meta was written a
      # handful of times per session; recording the child's winsize made it a
      # per-resize write, and a human dragging a window edge emits one per
      # frame. Measured through a real attach dragged across 250 shapes in 7.5s,
      # with another process doing what `alive_session` does: 90 of 294,728
      # reads came back unreadable, and 0 of 312,582 once this landed. `rename`
      # is atomic within a directory, so a reader sees either the whole previous
      # file or the whole new one.
      #
      # The temp name carries the writer's pid because two processes do write
      # this file — the CLI records `state`/`supervisor_pid` while the
      # supervisor records `state`/`child_pid`/winsize — and a shared temp path
      # would let them interleave into one corrupt file that then gets renamed
      # into place, which is worse than the torn read it replaces.
      def write_meta(name, meta)
        write_atomic(meta_path(name), JSON.generate(meta))
        meta
      end

      def read_meta(name)
        JSON.parse(File.read(meta_path(name)), symbolize_names: true)
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def update_meta(name, fields)
        current = read_meta(name)
        return nil unless current

        write_meta(name, current.merge(fields))
      end

      # Opened O_CREAT with an explicit mode and chmod'ed afterwards for the
      # same reason as the directory above: the mode argument is masked by
      # umask, and the file may already exist from an earlier run.
      # rubocop:disable Style/FileOpen -- the caller keeps this handle for the
      # life of the supervisor and closes it in its own teardown; the block
      # form would close it before a single event could be written.
      # Rewrites the transcript keeping only its recent tail, and returns the
      # reopened handle. The dropped byte count is carried in a `truncated`
      # event so cursors stay absolute: a reader adds it to its running offset
      # without emitting text, which means a cursor taken before a rotation
      # still means the same position in the stream.
      #
      # Scans only the part it keeps, and copies with `IO.copy_stream` so the
      # bytes never enter Ruby. Two earlier versions did not, and both were
      # worse than the problem: reading the file with `readlines` and parsing
      # every line twice put resident memory up by 229MB the moment a rotation
      # ran during a 45-minute soak, and streaming the lines but still parsing
      # them still cost 96MB per rotation. `total_output` comes from the caller,
      # which already tracks it, so the dropped region is never read at all.
      #
      # The caller's handle is closed only once the replacement is in place. It
      # used to be closed first, so any later failure left the supervisor holding
      # a *closed* handle it had no idea was closed, and `log_event`'s own rescue
      # then swallowed every subsequent write — recording stopped silently and
      # permanently for the rest of the session's life. Reproduced with EACCES on
      # the session directory (`harnesses/rotation_eacces.rb`): 200 further events
      # left the transcript 564_000 bytes behind the cursor, and making the
      # directory writable again did not resume recording, it widened the gap to
      # 654_000. A rotation that cannot happen must cost nothing but the rotation.
      def rotate_output(name, file, total_output)
        path = output_path(name)
        temp = "#{path}.rotating"
        begin
          prepare_rotation(path, temp, total_output)
          File.rename(temp, path)
        rescue IOError, SystemCallError
          # A half-written replacement is garbage the size of the tail, and
          # leaving it behind would also make the next attempt open it O_TRUNC.
          FileUtils.rm_f(temp)
          raise
        end
        file&.close
        open_output(name)
      end

      # Writes the replacement transcript — the `truncated` event accounting for
      # what is being dropped, then the tail being kept — without touching the
      # file the caller is still writing to.
      def prepare_rotation(path, temp, total_output)
        offset = tail_offset(path)
        kept = output_bytes_from(path, offset)
        write_private(temp) do |handle|
          handle.puts JSON.generate(event: 'truncated', ts: Time.now.to_f,
                                    dropped_bytes: total_output - kept)
          File.open(path, 'rb') { |src| IO.copy_stream(src, handle, nil, offset) }
        end
      end

      # The byte offset of the first whole line within LOG_KEEP_BYTES of the
      # end. Seeks rather than scans, so the size of what is being dropped costs
      # nothing.
      def tail_offset(path)
        size = File.size(path)
        return 0 if size <= LOG_KEEP_BYTES

        File.open(path, 'rb') do |handle|
          handle.seek(size - LOG_KEEP_BYTES)
          handle.gets # discard the partial line the seek landed inside
          handle.pos
        end
      end

      # Stream bytes the region being kept accounts for. Reads the `bytes` field
      # each event already records rather than parsing the event, so a line's
      # text is never materialized.
      #
      # A `truncated` event in that region accounts for bytes too — the ones a
      # failed write could not record — and they must be counted here for the
      # same reason the output is: rotation's new head event is
      # `total_output - kept`, so anything the kept region already accounts for
      # and this does not gets counted twice.
      #
      # A fragment left by a write that failed part-way is skipped, because
      # `Transcript.load` skips it: it still carries `"event":"output"` and
      # `"bytes":N`, so counting it would credit the kept region with output no
      # reader will ever see. The error would be permanent and silent — every
      # cursor after the rotation low by N, with no `truncated` event to explain
      # it — so the two decisions have to agree exactly.
      def output_bytes_from(path, offset)
        total = 0
        File.open(path, 'rb') do |handle|
          handle.seek(offset)
          while (line = handle.gets)
            next unless whole_record?(line)

            if line.include?('"event":"output"')
              total += line[/"bytes":(\d+)/, 1].to_i
            elsif line.include?('"event":"truncated"')
              total += line[/"dropped_bytes":(\d+)/, 1].to_i
            end
          end
        end
        total
      end

      # Whether a transcript line is a record `Transcript.load` will parse,
      # decided on its last byte rather than by parsing it. The two must agree
      # exactly: this feeds a rotation's head event and that reconstructs the
      # stream, so a line one counts and the other drops is a permanent cursor
      # skew. Parsing every line to be sure is the obvious answer and was already
      # rejected twice on cost — streaming the kept region and parsing it put
      # resident memory up 96MB per rotation — so the test is a byte comparison,
      # and `Supervisor::TORN_MARKER` is what makes it exact: `JSON.generate`
      # escapes newlines, so a record is always exactly one line ending `}`, and
      # a fragment the marker terminated ends in `n` and cannot parse either.
      #
      # A line with no trailing newline is the file's last, so there is at most
      # one per rotation and it is parsed outright. That is the one shape the
      # byte test cannot decide: a fragment cut inside a `text` field that
      # happens to hold a `}` ends on `}` without being a record.
      def whole_record?(line)
        size = line.bytesize
        return parseable?(line) unless line.getbyte(size - 1) == NEWLINE_BYTE

        size > 1 && line.getbyte(size - 2) == CLOSE_BRACE_BYTE
      end

      def parseable?(line)
        !JSON.parse(line).nil?
      rescue JSON::ParserError
        false
      end

      def output_bytes(line)
        event = JSON.parse(line, symbolize_names: true)
        event[:event] == 'output' ? event[:text].to_s.bytesize : 0
      rescue JSON::ParserError
        0
      end

      def output_size(name)
        File.size(output_path(name))
      rescue SystemCallError
        0
      end

      def open_output(name)
        path = output_path(name)
        file = File.open(path, File::WRONLY | File::CREAT | File::APPEND, FILE_MODE)
        File.chmod(FILE_MODE, path)
        file.sync = true
        file
      end
      # rubocop:enable Style/FileOpen

      private

      # The executable's own name, reduced to something usable as a directory
      # component. `ollama launch claude --model x` becomes `ollama`.
      def name_base(command)
        raw = File.basename(Array(command).first.to_s).downcase.gsub(/[^a-z0-9]+/, '-').delete_prefix('-')
        candidate = raw[0, 24].to_s.sub(/-+\z/, '')
        candidate.match?(/\A[a-z0-9]/) ? candidate : 'session'
      end

      def write_private(path, &block)
        File.open(path, File::WRONLY | File::CREAT | File::TRUNC, FILE_MODE, &block)
        File.chmod(FILE_MODE, path)
        path
      end

      # Serialise first, write the whole thing to a private temp file, then
      # rename over the target — the same shape `rotate_output` already uses for
      # the transcript, and for the same reason: readers of these files are
      # other processes with no lock to take.
      #
      # `rename` preserves the temp file's inode, so the 0600 mode
      # `write_private` set survives; the target's own previous mode is
      # irrelevant because it is unlinked by the rename.
      def write_atomic(path, contents)
        temp = "#{path}.#{Process.pid}.writing"
        begin
          write_private(temp) { |file| file.write(contents) }
          File.rename(temp, path)
        rescue StandardError
          FileUtils.rm_f(temp)
          raise
        end
        path
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
