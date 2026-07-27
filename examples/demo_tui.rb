#!/usr/bin/env ruby
# frozen_string_literal: true

# A small interactive demo program to actually play with rune against.
# Run it directly to see the raw TUI:
#   ruby examples/demo_tui.rb
#
# Or watch it live through rune, with a real terminal (a human types, rune
# forwards keystrokes and streams the output live, and logs every chunk as
# an NDJSON event you can tail from another terminal):
#   ruby bin/rune watch -- ruby examples/demo_tui.rb
#   ruby bin/rune watch --log=/tmp/demo-session.ndjson -- ruby examples/demo_tui.rb
#
# Or capture a single scripted run end-to-end instead of watching it live:
#   ruby bin/rune run --json -- ruby examples/demo_tui.rb
#
# It deliberately exercises the things rune's PromptDetector/TableParser/
# ANSI-stripping care about: a colored banner, a menu prompt, a y/n
# confirmation, a free-text prompt, a digit-percent progress bar (the exact
# shape that used to false-positive as a tcsh prompt), and a space-delimited
# table.

require_relative '../lib/rune/version'

$stdout.sync = true

CYAN = "\e[36m"
GREEN = "\e[32m"
YELLOW = "\e[33m"
BOLD = "\e[1m"
RESET = "\e[0m"

def banner
  puts "#{BOLD}#{CYAN}rune demo TUI#{RESET}"
  puts "#{CYAN}A small interactive program for dogfooding rune run / rune watch.#{RESET}"
  puts
end

def menu
  puts 'What would you like to see?'
  puts '  1) A table of fake data'
  puts '  2) A progress bar'
  puts '  3) A yes/no confirmation'
  puts '  4) A free-text prompt'
  puts '  q) Quit'
  print '> '
end

def show_table
  puts "#{'NAME'.ljust(14)} #{'STATUS'.ljust(7)} VERSION"
  puts "#{'fledge-plugin'.ljust(14)} #{'active'.ljust(7)} 1.0.0"
  puts "#{'rune'.ljust(14)} #{'active'.ljust(7)} #{Rune::VERSION}"
end

def show_progress
  0.step(100, 20) do |pct|
    print "\rDownloading... #{pct}%"
    sleep 0.15
  end
  puts "\rDownloading... 100% #{GREEN}done#{RESET}"
end

def confirm
  print 'Continue? (y/n) '
  answer = $stdin.gets&.strip
  puts answer&.match?(/\Ay/i) ? "#{GREEN}Confirmed.#{RESET}" : "#{YELLOW}Cancelled.#{RESET}"
end

def ask_name
  print 'What is your name? '
  name = $stdin.gets&.strip
  puts "Hello, #{BOLD}#{name}#{RESET}!"
end

banner
loop do
  menu
  case $stdin.gets&.strip
  when '1' then show_table
  when '2' then show_progress
  when '3' then confirm
  when '4' then ask_name
  when 'q', nil
    puts 'Goodbye!'
    break
  else puts "#{YELLOW}Not a valid option.#{RESET}"
  end
  puts
end
