# frozen_string_literal: true

require 'optparse'

module XZST
  class CLI
    @commands = {}

    class << self
      attr_reader :commands

      def register(command_class)
        # Defer registration until command_name is set via TracePoint on class :end
        TracePoint.new(:end) do |tp|
          if tp.self == command_class && command_class.command_name
            @commands[command_class.command_name] = command_class
            tp.disable
          end
        end.enable
      end

      def run(argv = ARGV, io: $stdout)
        new(io:).run(argv)
      end
    end

    def initialize(io: $stdout)
      @io = io
      @json_mode = false
    end

    def run(argv)
      args = argv.dup

      # Extract global flags
      @json_mode = args.delete('--json') ? true : false

      command_name = args.shift
      renderer = Renderer.new(io: @io, json_mode: @json_mode)

      if command_name.nil? || command_name == 'help'
        command_name = 'help'
        result = show_help
      elsif ['--version', '-v'].include?(command_name)
        command_name = 'version'
        result = run_command(command_name, args)
      else
        result = run_command(command_name, args)
      end

      # Find the command instance for human rendering
      command_class = self.class.commands[command_name]
      command_instance = command_class&.new

      renderer.render(result,
                      human_block: (->(data, io) { command_instance.human_render(data, io) } if command_instance))

      exit result.exit_code
    end

    private

    def run_command(name, args)
      command_class = self.class.commands[name]
      return Result.failure("Unknown command: #{name}. Run 'xzst help' for available commands.") unless command_class

      command = command_class.new
      command.call(args, { json: @json_mode })
    rescue StandardError => e
      Result.failure(e.message)
    end

    def show_help
      Result.success({
                       commands: self.class.commands.map { |n, c| { name: n, summary: c.command_summary } },
                       version: VERSION
                     })
    end

    def help_human_render(data, io)
      io.puts "\e[1;35mxzst\e[0m v#{data[:version]}"
      io.puts ''
      io.puts 'Commands:'
      data[:commands].each do |cmd|
        io.puts format("  \e[1m%-20<name>s\e[0m %<summary>s", name: cmd[:name], summary: cmd[:summary])
      end
      io.puts ''
      io.puts 'Global flags:'
      io.puts "  \e[1m--json\e[0m               Output as JSON (agent mode)"
      io.puts ''
      io.puts 'Pipe or redirect output to automatically get JSON.'
    end
  end
end
