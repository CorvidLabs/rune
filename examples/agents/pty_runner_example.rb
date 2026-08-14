#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/rune'

puts '=== Rune PTY Runner Example ==='
puts 'Running `git status` inside a pseudo-terminal...'

runner = Rune::PTYRunner.new('git status')
result = runner.run

if result.success?
  puts "\n✅ Command succeeded in #{result.data[:duration_ms]}ms:"
  puts "Exit Code: #{result.data[:exit_code]}"
  puts "Clean Output:\n#{result.data[:clean_output]}"
else
  puts "❌ Command failed: #{result.error}"
end
