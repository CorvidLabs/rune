#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/rune'

puts '=== Rune Table Parser Example ==='

raw_table = <<~TABLE
  NAME           STATUS   VERSION   ECOSYSTEM
  fledge-plugin  active   1.0.0     corvidlabs
  rust-cli       ready    2.1.0     corvidlabs
  rune           active   0.1.0     corvidlabs
TABLE

parsed_rows = Rune::Parsers::TableParser.parse(raw_table)

puts 'Parsed Table Array of Hashes:'
parsed_rows.each_with_index do |row, idx|
  puts "Row #{idx + 1}: #{row.inspect}"
end
