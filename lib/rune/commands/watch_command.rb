# frozen_string_literal: true

require_relative '../pty_watcher'

module Rune
  module Commands
    class WatchCommand < Command
      name 'watch'
      summary 'Interactively drive a command in a PTY with live passthrough and an NDJSON event log'

      def call(args, _options)
        log_path, remaining = extract_log(args)
        clean_args = remaining.first == '--' ? remaining[1..] : remaining
        return Result.failure('No command specified. Usage: rune watch [--log=PATH] <command...>') if clean_args.empty?

        log = log_path ? File.open(log_path, 'a') : $stderr
        begin
          PTYWatcher.new(clean_args, log: log).watch
        ensure
          log.close if log_path
        end
      end

      def human_render(data, io)
        io.puts "\n[rune watch] session ended (exit #{data[:exit_code]})"
      end

      private

      # --log=PATH: write the NDJSON event stream to a file instead of
      # stderr (useful when stderr isn't easily separable from the human's
      # view of the session). Otherwise stderr works out of the box with
      # plain shell redirection: `rune watch -- cmd 2>session.ndjson`.
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
