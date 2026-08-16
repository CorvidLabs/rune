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
    end

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
