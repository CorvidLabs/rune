# frozen_string_literal: true

require 'optparse'

module Rune
  class CLI
    @commands = {}

    class << self
      attr_reader :commands

      def register(command_class)
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
      @ndjson_mode = false
    end

    def run(argv)
      args = argv.dup
      @json_mode = args.delete('--json') ? true : false
      @ndjson_mode = args.delete('--ndjson') ? true : false

      command_name = resolve_command_name(args.shift)
      result = command_name == 'help' ? show_help : run_command(command_name, args)

      render_result(command_name, result)
      exit result.exit_code
    end

    private

    def resolve_command_name(name)
      return 'help' if name.nil? || name == 'help'
      return 'version' if ['--version', '-v'].include?(name)

      name
    end

    def render_result(command_name, result)
      renderer = Renderer.new(io: @io, json_mode: @json_mode, ndjson_mode: @ndjson_mode)
      command_instance = self.class.commands[command_name]&.new

      renderer.render(result, human_block: lambda { |data, io|
        if command_instance
          command_instance.human_render(data, io)
        else
          help_human_render(data, io)
        end
      })
    end

    def run_command(name, args)
      command_class = self.class.commands[name]
      return Result.failure("Unknown command: #{name}. Run 'rune help' for available commands.") unless command_class

      command = command_class.new
      command.call(args, { json: @json_mode, ndjson: @ndjson_mode })
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
      io.puts "\e[1;35mrune\e[0m v#{data[:version]}"
      io.puts ''
      io.puts 'Commands:'
      data[:commands].each do |cmd|
        io.puts format("  \e[1m%-20<name>s\e[0m %<summary>s", name: cmd[:name], summary: cmd[:summary])
      end
      io.puts ''
      io.puts 'Global flags:'
      io.puts '  --json               Output as JSON (agent mode)'
      io.puts '  --ndjson             Stream output as JSON lines (live agent mode)'
      io.puts ''
      io.puts 'Pipe or redirect output to automatically get JSON.'
    end
  end
end
