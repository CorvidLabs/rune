# frozen_string_literal: true

module Rune
  class Script
    Step = Struct.new(:type, :payload)

    attr_reader :steps

    def initialize
      @steps = []
    end

    def wait_for(pattern)
      @steps << Step.new(:wait_for, pattern)
    end

    def send_keys(keys)
      @steps << Step.new(:send_keys, keys.to_s)
    end

    def pause(seconds)
      @steps << Step.new(:pause, seconds)
    end

    class << self
      def define(&)
        script = new
        script.instance_eval(&) if block_given?
        script
      end
    end
  end
end
