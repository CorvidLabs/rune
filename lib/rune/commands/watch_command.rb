# frozen_string_literal: true

require 'tmpdir'
require 'tempfile'
require_relative '../pty_watcher'

module Rune
  module Commands
    class WatchCommand < Command
      name 'watch'
      summary 'Interactively drive a command in a PTY with live passthrough and an NDJSON event log'
      usage 'rune watch [--log=PATH] [--] <command...>'
      flag '--log=PATH', 'Write the NDJSON event log here instead of a temp file. Before `--` only.'

      def call(args, options)
        return Result.failure('rune watch requires a real terminal (stdin is not a TTY).') unless $stdin.tty?

        log_path, remaining, log_error = extract_log(args)
        return Result.failure(log_error) if log_error

        clean_args = remaining.first == '--' ? remaining[1..] : remaining
        return Result.failure('No command specified. Usage: rune watch [--log=PATH] <command...>') if clean_args.empty?

        # Defaults to a temp file, not stderr: stderr shares the human's
        # terminal with the live passthrough by default, interleaving JSON
        # noise into an otherwise-clean interactive session. Announce the
        # path once, up front, so a human (tail -f it from another pane) or
        # an agent knows where to watch. `--log=/dev/stderr` still works if
        # stderr is genuinely wanted (e.g. a wrapping process capturing it).
        log_path, log = open_log(log_path)
        warn "[rune watch] live event log: #{log_path}"
        begin
          result = PTYWatcher.new(clean_args, log: log, output: display_stream(options)).watch
        ensure
          log.close
        end
        attach_log_path(result, log_path)
      end

      # human_render runs on a separate Command instance from #call (CLI#
      # render_result builds its own), so the closing message can't reach an
      # ivar set here — the log path has to travel through Result#data itself.
      def human_render(data, io)
        icon = data[:exit_code].zero? ? "\e[32m✓\e[0m" : "\e[33m✗\e[0m"
        io.puts ''
        io.puts "#{icon} \e[1msession ended\e[0m (exit #{data[:exit_code]}, #{format_duration(data[:duration_ms])})"
        io.puts "  log: \e[36m#{data[:log_path]}\e[0m" if data[:log_path]
      end

      private

      # Where the wrapped child's live bytes go. This is the one command whose
      # `#call` produces output as a side effect while it runs, so it has to
      # make the agent-mode decision itself rather than leaving it to the
      # Renderer — by the time the Renderer sees the Result, the whole session
      # has already been displayed. Passing this explicitly is load-bearing:
      # `PTYWatcher`'s `output:` defaults to `$stdout`, and not passing it at
      # all meant the child's raw bytes landed on the same stream the Renderer
      # then wrote the JSON envelope to, so `rune watch --json` emitted stdout
      # that did not parse ("unexpected character: 'X' at line 1 column 1").
      #
      # stderr rather than /dev/null: a human is still driving the session even
      # when a wrapping process captures stdout, so the live view has to remain
      # visible somewhere. Same reasoning already puts the log-path
      # announcement on stderr.
      def display_stream(options)
        agent_mode?(options) ? $stderr : $stdout
      end

      # Mirrors `Renderer#agent_mode?` one layer earlier. It reads the real
      # `$stdout` rather than the CLI's injected io because the live
      # passthrough writes to the real process stdout by nature — there is no
      # meaningful "watch a TUI into a StringIO" — and because `#call` has no
      # access to the Renderer's stream anyway.
      def agent_mode?(options)
        options[:json] || options[:ndjson] || !$stdout.tty?
      end

      # A watched session can run for seconds, minutes, or hours, unlike
      # `rune run`'s usual sub-second commands — raw milliseconds
      # (e.g. "78104.43ms") is unreadable at that scale. Under a minute, a
      # plain seconds figure is already exact enough on its own. Coarser
      # than that (Mm Ss / Hh Mm Ss) loses sub-second precision, so the
      # exact seconds are appended in parentheses there — but not below a
      # minute, where restating the same seconds figure twice is just noise.
      def format_duration(duration_ms)
        seconds = duration_ms / 1000.0
        return "#{duration_ms.round}ms" if duration_ms < 1000
        return "#{seconds.round(2)}s" if seconds < 60

        coarse = if seconds < 3600
                   "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
                 else
                   "#{(seconds / 3600).floor}h #{((seconds % 3600) / 60).floor}m #{(seconds % 60).round}s"
                 end
        "#{coarse}, #{seconds.round(2)}s"
      end

      # Rebuilds the Result with log_path folded into its data instead of
      # mutating it in place: Result#data is whatever PTYWatcher handed back,
      # and relying on it staying a plain mutable Hash forever is a needless
      # coupling to another class's internals.
      def attach_log_path(result, log_path)
        return result unless result.success?

        Result.success(result.data.merge(log_path: log_path), exit_code: result.exit_code)
      end

      def open_log(log_path)
        if log_path
          log = File.open( # rubocop:disable Style/FileOpen -- kept open past this line intentionally
            log_path, File::WRONLY | File::CREAT | File::APPEND, 0o600
          )
          return [log_path, log]
        end

        log = Tempfile.create(['rune-watch-', '.ndjson'], Dir.tmpdir)
        [log.path, log]
      end

      # --log=PATH: write the NDJSON event stream to a specific file instead
      # of the default temp path. Matches an empty value (`--log=`) too,
      # rather than leaving it unrecognized — previously that silently fell
      # through untouched into the wrapped command's own argv instead of
      # producing a clear error.
      def extract_log(args)
        separator_index = args.index('--')
        head = separator_index ? args[0...separator_index] : args
        tail = separator_index ? args[separator_index..] : []

        log_path = nil
        error = nil
        head = head.reject do |arg|
          match = arg.match(/\A--log=(.*)\z/)
          next false unless match

          if match[1].empty?
            error = '--log requires a path, e.g. --log=/tmp/session.ndjson'
          else
            log_path = match[1]
          end
          true
        end

        [log_path, head + tail, error]
      end
    end
  end
end
