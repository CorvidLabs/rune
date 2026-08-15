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

      def write_meta(name, meta)
        write_private(meta_path(name)) { |file| file.write(JSON.generate(meta)) }
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
    end
    # rubocop:enable Metrics/ClassLength
  end
end
