# frozen_string_literal: true

module Rune
  class Command
    class << self
      attr_reader :command_name, :command_summary, :command_usage

      def name(cmd_name) = @command_name = cmd_name
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

      def inherited(subclass)
        super
        CLI.register(subclass) if subclass.is_a?(Class)
      end
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
