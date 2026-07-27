# frozen_string_literal: true

module XZST
  class Command
    class << self
      attr_reader :command_name, :command_summary

      def name(cmd_name) = @command_name = cmd_name
      def summary(text) = @command_summary = text

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
