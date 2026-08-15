#!/usr/bin/env ruby
# frozen_string_literal: true

# Turning real CLI output into data you can branch on — the library half of
# rune, with no sessions and no TTY involved.
#
#   ruby examples/agents/parsing_pipeline.rb
#
# `PTYRunner` gets the text, the parsers turn it into structures, and the
# calling program makes a decision. The point is that none of this needs the
# wrapped tool to have a `--json` flag: rune runs it in a pty, so a tool that
# only ever prints a human table is still usable programmatically.

require_relative '../../lib/rune'

def heading(text) = puts("\n\e[1m#{text}\e[0m")

# --- 1. Any command, structured ---------------------------------------------
heading('1. run any command and read a structured Result')
result = Rune::PTYRunner.new(%w[git log --oneline -3]).run
puts "  exit_code=#{result.data[:exit_code]}  duration=#{result.data[:duration_ms]}ms"
puts "  prompt_detected=#{result.data[:prompt_detected]}"
result.data[:clean_output].lines.first(3).each { |line| puts "    #{line.chomp}" }

# --- 2. A human table becomes an array of hashes -----------------------------
heading('2. parse a table a tool only ever meant for human eyes')
listing = Rune::PTYRunner.new(['printf', <<~TABLE]).run
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
  rust-cli       ready    2.1.0
TABLE
Rune::Parsers::TableParser.parse(listing.data[:clean_output]).each do |row|
  puts "  #{row.inspect}"
end

# Know the heuristic's limits. Column *detection* is whitespace-based, so a
# right-aligned numeric column (as `ps` and `df` produce) can be split in the
# wrong place. When a table is ambiguous, say what it is rather than hoping:
heading('2b. pin the delimiter when auto-detection would guess wrong')
ambiguous = <<~PIPE
  NAME          | STATUS | VERSION
  fledge-plugin | active | 1.0.0
  rust-cli      | ready  | 2.1.0
PIPE
puts "  :auto -> #{Rune::Parsers::TableParser.parse(ambiguous).first.inspect}"
puts "  :pipe -> #{Rune::Parsers::TableParser.parse(ambiguous, format: :pipe).first.inspect}"

# --- 3. key: value output becomes a typed hash -------------------------------
heading('3. parse key/value output')
kv = Rune::PTYRunner.new(%w[ruby -v]).run.data[:clean_output]
puts "  raw: #{kv.strip}"
pairs = Rune::Parsers::KeyValueParser.parse("version: #{RUBY_VERSION}\nplatform: #{RUBY_PLATFORM}\njit: false")
puts "  parsed: #{pairs.inspect}"

# --- 4. Bounding output you did not write ------------------------------------
heading('4. bound a chatty command so it cannot blow up your context')
chatter = <<~'RUBY'
  500.times { |i| puts "line #{i}" }
RUBY
noisy = Rune::PTYRunner.new(['ruby', '-e', chatter], tail_lines: 3).run
puts "  truncated=#{noisy.data[:truncated]} omitted_lines=#{noisy.data[:omitted_lines]}"
puts noisy.data[:clean_output].lines.map { |line| "    #{line.chomp}" }.join("\n")

capped = Rune::PTYRunner.new(['ruby', '-e', chatter], max_output_bytes: 120).run
puts "  max_output: kept #{capped.data[:clean_output].bytesize}B, omitted #{capped.data[:omitted_bytes]}B (head+tail)"

# --- 5. Exit codes are preserved, not swallowed ------------------------------
heading('5. failures stay legible')
%w[false nonexistent-command-xyz].each do |command|
  outcome = Rune::PTYRunner.new([command]).run
  puts "  #{command.ljust(24)} -> exit_code=#{outcome.data[:exit_code]}"
end
puts '  (127 = not found, 126 = not executable — same convention as a shell)'
