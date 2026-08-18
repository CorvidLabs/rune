# frozen_string_literal: true

module Rune
  class Command
    # A token shaped like one of rune's own long flags: `--`, a letter, then flag characters only,
    # optionally `=value`.
    #
    # Deliberately narrow, because in every command that has one the same argv position also
    # carries text the caller means as *input* or as the wrapped command's own argv. `--- section
    # ---` (second character is not a letter, and it holds spaces) and `--foo bar` as one token are
    # not flags and are still passed through; only a token that could not plausibly be anything but
    # a mistyped flag matches. `/m` so a value carrying a newline is still recognized by its name.
    FLAG_SHAPED = /\A--[A-Za-z][A-Za-z0-9_-]*(?:=.*)?\z/m

    class << self
      attr_reader :command_name, :command_summary, :command_usage

      # Whether `token` looks like a long flag rune could have meant to own.
      #
      # `rune session frobnicate` has always been rejected, but a mistyped *flag* was not: it
      # matched nothing, fell through to the argv the command passes on, and was then typed at a
      # child or execed as a program name. Commands use this to tell "you misspelled a flag" from
      # "this is your input".
      def flag_shaped?(token) = FLAG_SHAPED.match?(token)

      def name(cmd_name = nil)
        return super() if cmd_name.nil?

        @command_name = cmd_name
        CLI.register(self)
        cmd_name
      end

      def summary(text) = @command_summary = text

      # One-line invocation shape shown by `rune <cmd> --help`, e.g.
      # "rune run [--timeout=SECONDS] [--] <command...>". Optional: a command
      # that declares none falls back to a bare "rune <name>".
      def usage(text) = @command_usage = text

      # Declares a command-specific flag for `rune <cmd> --help`. Until this
      # existed, `--timeout` and `--log` were discoverable only from `specs/`
      # and from the error you got for using them wrong.
      def flag(spec, description)
        command_flags << { flag: spec, description: description }
      end

      def command_flags = @command_flags ||= []

      # Declares one subcommand so `rune <command> --help --json` can list them
      # as data, in the same `{name, summary}` shape `rune --help` already uses
      # for top-level commands.
      #
      # Without this the surface was structured at the top level and a string
      # one level down: `rune session --help --json` carried the subcommands
      # only inside its `usage` line, as `<start|send|read|...>`. An agent
      # discovering the CLI had to parse JSON for one level and then split on
      # `|` for the next, which a field report flagged after hitting exactly
      # that. Commands without subcommands declare none and the key stays
      # absent, so nothing that reads the old payload changes shape.
      def subcommand(name, description)
        command_subcommands << { name: name.to_s, summary: description }
      end

      def command_subcommands = @command_subcommands ||= []

      # Rejects a flag-shaped token that reached the wrapped command's argv.
      #
      # `run` and `watch` both own flags and both hand everything they do not recognise to the
      # child, so an unrecognised flag is executed rather than reported. `run` guarded this and
      # `watch` did not: measured through a real controlling terminal, `rune watch --timeout 5 --
      # echo hi` exited 127 with the child never running, because `--timeout` was exec'd as the
      # program. That is the worse failure of the two — `run` at least says something.
      #
      # Shared here rather than copied because the two had already drifted once: `run` grew the
      # inline-value branch and `watch` had no guard at all to grow it in.
      def flag_error(leftovers, value_flags)
        unknown = leftovers.take_while { |token| flag_shaped?(token) }.first
        return nil unless unknown

        name = unknown.split('=', 2).first
        template = value_flags.include?(name) ? INLINE_VALUE_ERROR : UNKNOWN_FLAG_ERROR
        format(template, name: name, command: command_name)
      end
    end

    # A flag the command owns, spelled correctly, whose value was given with a space. The general
    # message below got this wrong three ways: it called a flag rune owns "Unknown", it asserted a
    # position error when the flag was already before the separator, and following its remedy hands
    # the flag to the child instead of applying it.
    INLINE_VALUE_ERROR = '%<name>s takes its value inline: %<name>s=VALUE. To pass it to the ' \
                         'command instead: rune %<command>s -- <command> %<name>s VALUE'

    UNKNOWN_FLAG_ERROR = "Unknown option: %<name>s. rune's own flags are recognized only before " \
                         'the wrapped command; to pass this one to that command instead, put the ' \
                         'command first or use a separator: rune %<command>s -- <command> %<name>s'

    # Override in subclasses
    def call(args, options)
      raise NotImplementedError, "#{self.class}#call must be implemented"
    end

    # Optional: override to provide human-formatted output
    def human_render(_data, _io)
      nil # Use default renderer
    end
  end
end
