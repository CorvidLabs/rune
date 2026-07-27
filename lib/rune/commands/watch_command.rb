# frozen_string_literal: true

require 'tmpdir'
require_relative '../pty_watcher'

module Rune
  module Commands
    class WatchCommand < Command
      name 'watch'
      summary 'Interactively drive a command in a PTY with live passthrough and an NDJSON event log'

      def call(args, _options)
        return Result.failure('rune watch requires a real terminal (stdin is not a TTY).') unless $stdin.tty?

        log_path, remaining = extract_log(args)
        clean_args = remaining.first == '--' ? remaining[1..] : remaining
        return Result.failure('No command specified. Usage: rune watch [--log=PATH] <command...>') if clean_args.empty?

        # Defaults to a temp file, not stderr: stderr shares the human's
        # terminal with the live passthrough by default, interleaving JSON
        # noise into an otherwise-clean interactive session. Announce the
        # path once, up front, so a human (tail -f it from another pane) or
        # an agent knows where to watch. `--log=/dev/stderr` still works if
        # stderr is genuinely wanted (e.g. a wrapping process capturing it).
        log_path ||= default_log_path
        warn "[rune watch] live event log: #{log_path}"
        log = File.open(log_path, 'a') # rubocop:disable Style/FileOpen -- kept open past this line intentionally
        begin
          result = PTYWatcher.new(clean_args, log: log).watch
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
        io.puts "#{icon} \e[1msession ended\e[0m (exit #{data[:exit_code]}, #{data[:duration_ms]}ms)"
        io.puts "  log: \e[36m#{data[:log_path]}\e[0m" if data[:log_path]
      end

      private

      # Rebuilds the Result with log_path folded into its data instead of
      # mutating it in place: Result#data is whatever PTYWatcher handed back,
      # and relying on it staying a plain mutable Hash forever is a needless
      # coupling to another class's internals.
      def attach_log_path(result, log_path)
        return result unless result.success?

        Result.success(result.data.merge(log_path: log_path), exit_code: result.exit_code)
      end

      def default_log_path
        File.join(Dir.tmpdir, "rune-watch-#{Process.pid}-#{Time.now.to_i}.ndjson")
      end

      # --log=PATH: write the NDJSON event stream to a specific file instead
      # of the default temp path.
      def extract_log(args)
        separator_index = args.index('--')
        head = separator_index ? args[0...separator_index] : args
        tail = separator_index ? args[separator_index..] : []

        log_path = nil
        head = head.reject do |arg|
          match = arg.match(/\A--log=(.+)\z/)
          next false unless match

          log_path = match[1]
          true
        end

        [log_path, head + tail]
      end
    end
  end
end
