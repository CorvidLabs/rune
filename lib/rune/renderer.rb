# frozen_string_literal: true

require 'json'

module Rune
  class Renderer
    attr_reader :io, :json_mode, :ndjson_mode

    def initialize(io: $stdout, json_mode: false, ndjson_mode: false)
      @io = io
      @json_mode = json_mode
      @ndjson_mode = ndjson_mode
    end

    def agent_mode?
      json_mode || ndjson_mode || !io.tty?
    end

    def render(result, human_block: nil)
      if ndjson_mode
        render_ndjson(result)
      elsif agent_mode?
        render_json(result)
      else
        render_human(result, human_block)
      end
    end

    def render_event(event_type, payload = {})
      return unless ndjson_mode

      io.puts JSON.generate({ event: event_type.to_s }.merge(payload))
      io.flush
    end

    private

    def render_json(result)
      io.puts JSON.generate(result.to_h)
    end

    def render_ndjson(result)
      event = result.success? ? :result : :error
      io.puts JSON.generate({ event: event.to_s }.merge(result.to_h))
      io.flush
    end

    def render_human(result, human_block)
      if result.failure?
        io.puts "\e[31m✗ #{result.error}\e[0m"
      elsif human_block
        human_block.call(result.data, io)
      else
        result.data&.each { |k, v| io.puts "  #{k}: #{v}" }
      end
    end
  end
end
