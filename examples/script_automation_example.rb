#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/rune'

puts '=== Rune Script Automation Example ==='

script = Rune::Script.define do
  wait_for(/Select a plugin/)
  send_keys "q\n"
  pause 0.5
end

puts "Defined script with #{script.steps.size} steps:"
script.steps.each_with_index do |step, idx|
  puts "  Step #{idx + 1}: #{step.type} -> #{step.payload.inspect}"
end
