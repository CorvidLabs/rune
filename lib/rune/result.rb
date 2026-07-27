# frozen_string_literal: true

module Rune
  class Result
    attr_reader :status, :data, :error

    def initialize(status:, data: nil, error: nil)
      @status = status
      @data = data
      @error = error
    end

    def success? = status == :ok
    def failure? = status == :error

    def self.success(data) = new(status: :ok, data:)
    def self.failure(error, data: nil) = new(status: :error, data:, error:)

    def to_h
      h = { status: status.to_s }
      h[:data] = data if data
      h[:error] = error if error
      h
    end

    def exit_code = success? ? 0 : 1
  end
end
