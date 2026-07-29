# frozen_string_literal: true

module Rune
  # Builds and renders `rune --help`, `rune <command> --help`, and
  # `rune help [command]`.
  #
  # Split out of `CLI` rather than living there: `CLI`'s job is to route an
  # argv to a command and render whatever `Result` comes back, and help is a
  # presentation concern with its own payload shapes. Keeping it here also
  # keeps the help text next to the flag metadata it renders.
  class Help
    # Recognized only before the first `--`, same rule as `--json`/`--ndjson`
    # (see `cli.spec.md` invariant 9), so `rune run -- mytool --help` passes
    # `--help` through to the wrapped command untouched.
    FLAGS = %w[--help -h].freeze

    GLOBAL_FLAGS = [
      { flag: '--json', description: 'Output as JSON (agent mode)' },
      { flag: '--ndjson', description: 'Output a newline-delimited JSON envelope' },
      { flag: '--help, -h', description: 'Show help for rune, or for one command' }
    ].freeze

    # Removes any help flag from the pre-separator portion of `args` (in
    # place, so it composes with the output-mode extraction that ran before
    # it) and reports whether one was present.
    def self.extract_flag!(args)
      separator_index = args.index('--')
      head = separator_index ? args[0...separator_index] : args
      tail = separator_index ? args[separator_index..] : []

      requested = false
      filtered_head = head.reject do |argument|
        help_flag = FLAGS.include?(argument)
        requested ||= help_flag
        help_flag
      end

      args.replace(filtered_head + tail)
      requested
    end

    def initialize(commands)
      @commands = commands
    end

    def overview
      Result.success({
                       commands: @commands.map { |name, klass| { name: name, summary: klass.command_summary } },
                       global_flags: GLOBAL_FLAGS,
                       version: VERSION
                     })
    end

    # Structured, not merely printed: an agent running
    # `rune run --help --json` gets the usage string and flag list as data and
    # can discover the CLI surface without scraping the human rendering.
    def for_command(command_name)
      command_class = @commands[command_name]
      return Result.failure("Unknown command: #{command_name}. Run 'rune help' for available commands.") unless
        command_class

      Result.success({
                       command: command_name,
                       summary: command_class.command_summary,
                       usage: command_class.command_usage || "rune #{command_name}",
                       flags: command_class.command_flags,
                       global_flags: GLOBAL_FLAGS,
                       version: VERSION
                     })
    end

    def render(data, io)
      data[:command] ? render_command(data, io) : render_overview(data, io)
      io.puts ''
      io.puts 'Global flags:'
      render_flags(data[:global_flags], io)
    end

    private

    def render_overview(data, io)
      io.puts "\e[1;35mrune\e[0m v#{data[:version]}"
      io.puts ''
      io.puts 'Commands:'
      data[:commands].each do |cmd|
        io.puts format("  \e[1m%-20<name>s\e[0m %<summary>s", name: cmd[:name], summary: cmd[:summary])
      end
      io.puts ''
      io.puts "Run 'rune <command> --help' for command-specific flags."
      io.puts 'Pipe or redirect output to automatically get JSON.'
    end

    def render_command(data, io)
      io.puts "\e[1;35mrune #{data[:command]}\e[0m — #{data[:summary]}"
      io.puts ''
      io.puts 'Usage:'
      io.puts "  #{data[:usage]}"
      return if data[:flags].empty?

      io.puts ''
      io.puts 'Flags:'
      render_flags(data[:flags], io)
    end

    def render_flags(flags, io)
      flags.each do |entry|
        io.puts format("  \e[1m%-22<flag>s\e[0m %<description>s", flag: entry[:flag], description: entry[:description])
      end
    end
  end
end
