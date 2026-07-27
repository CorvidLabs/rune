# frozen_string_literal: true

require 'json'

module Rune
  class Renderer
    attr_reader :io, :json_mode

    def initialize(io: $stdout, json_mode: false)
      @io = io
      @json_mode = json_mode
    end

    def agent_mode?
      json_mode || !io.tty?
    end

    def render(result, human_block: nil)
      if agent_mode?
        render_json(result)
      else
        render_human(result, human_block)
      end
    end

    private

    def render_json(result)
      io.puts JSON.generate(result.to_h)
    end

    def render_human(result, human_block)
      if result.failure?
        io.puts "\e[31m✗ #{result.error}\e[0m"
      elsif human_block
        human_block.call(result.data, io)
      else
        # Default: pretty print the data
        result.data&.each { |k, v| io.puts "  #{k}: #{v}" }
      end
    end
  end
end
