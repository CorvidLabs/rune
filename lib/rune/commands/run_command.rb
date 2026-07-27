# frozen_string_literal: true

require_relative '../pty_runner'

module Rune
  module Commands
    class RunCommand < Command
      name 'run'
      summary 'Execute any CLI command in a PTY and return structured output'

      def call(args, _options)
        clean_args = args.reject { |a| a == '--' }
        return Result.failure('No command specified. Usage: rune run <command...>') if clean_args.empty?

        PTYRunner.new(clean_args).run
      end

      def human_render(data, io)
        icon = data[:exit_code].zero? ? "\e[32m✓\e[0m" : "\e[31m✗\e[0m"
        header = "#{icon} \e[1m#{data[:command]}\e[0m " \
                 "(\e[36m#{data[:duration_ms]}ms\e[0m, exit \e[1m#{data[:exit_code]}\e[0m)"

        io.puts header
        io.puts ''
        io.puts data[:clean_output]
      end
    end
  end
end
