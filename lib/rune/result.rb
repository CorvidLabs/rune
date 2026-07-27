# frozen_string_literal: true

module Rune
  class Result
    attr_reader :status, :data, :error

    def initialize(status:, data: nil, error: nil, exit_code: nil)
      @status = status
      @data = data
      @error = error
      @exit_code_override = exit_code
    end

    def success? = status == :ok
    def failure? = status == :error

    def self.success(data, exit_code: nil) = new(status: :ok, data:, exit_code:)
    def self.failure(error, data: nil, exit_code: nil) = new(status: :error, data:, error:, exit_code:)

    def to_h
      h = { status: status.to_s }
      h[:data] = data if data
      h[:error] = error if error
      h
    end

    # The process exit status a CLI should exit with, distinct from the
    # `exit_code` a wrapped command may report in `data`. Defaults to the
    # usual success/failure mapping, but a command can override it (e.g.
    # PTYRunner exits with the wrapped command's own exit code so `rune run`
    # composes correctly with shell `&&`/`||`/`set -e`).
    def exit_code
      return @exit_code_override if @exit_code_override

      success? ? 0 : 1
    end
  end
end
