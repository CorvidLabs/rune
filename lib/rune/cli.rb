# frozen_string_literal: true

module Rune
  class CLI
    @commands = {}

    class << self
      attr_reader :commands

      def register(command_class)
        command_name = command_class.command_name
        @commands[command_name] = command_class if command_name
      end

      def run(argv = ARGV, io: $stdout)
        new(io: io).run(argv)
      end
    end

    def initialize(io: $stdout)
      @io = io
      @json_mode = false
      @ndjson_mode = false
    end

    def run(argv)
      args = argv.dup
      args = extract_output_modes(args)
      help_requested = Help.extract_flag!(args)
      command_name = resolve_command_name(args.shift)
      help_mode = command_name == 'help' || help_requested

      result = if command_name == 'help'
                 show_help(args.shift)
               elsif help_requested
                 show_help(command_name)
               else
                 run_command(command_name, args)
               end

      render_result(command_name, result, help_mode: help_mode)
      exit result.exit_code
    end

    private

    def extract_output_modes(args)
      separator_index = args.index('--')
      head = separator_index ? args[0...separator_index] : args
      tail = separator_index ? args[separator_index..] : []
      @json_mode = head.delete('--json') ? true : false
      @ndjson_mode = head.delete('--ndjson') ? true : false
      head + tail
    end

    def resolve_command_name(name)
      return 'help' if name.nil? || name == 'help'
      return 'version' if ['--version', '-v'].include?(name)

      name
    end

    def render_result(command_name, result, help_mode:)
      renderer = Renderer.new(io: @io, json_mode: @json_mode, ndjson_mode: @ndjson_mode)
      # Help for a command must not be rendered by that command — `rune run
      # --help` resolves command_name to "run", and RunCommand#human_render
      # expects a PTY result, not a help payload.
      command_instance = help_mode ? nil : self.class.commands[command_name]&.new

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

    def show_help(command_name = nil)
      help = Help.new(self.class.commands)
      command_name ? help.for_command(command_name) : help.overview
    end

    def help_human_render(data, io)
      Help.new(self.class.commands).render(data, io)
    end
  end
end
