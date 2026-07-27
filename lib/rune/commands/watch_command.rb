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
          PTYWatcher.new(clean_args, log: log).watch
        ensure
          log.close
        end
      end

      def human_render(data, io)
        io.puts "\n[rune watch] session ended (exit #{data[:exit_code]})"
      end

      private

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
