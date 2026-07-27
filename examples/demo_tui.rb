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
# The top-level menu is a real arrow-key selector (Up/Down + Enter, or q to
# quit) rather than type-a-number-and-press-Enter, specifically to exercise
# raw single-byte/escape-sequence input over the PTY — the thing rune's
# `input:`/`Script#send_keys` byte-forwarding and `rune watch`'s live
# keystroke forwarding actually have to get right, which a purely
# line-buffered `gets` menu never touches. It also exercises the things
# rune's PromptDetector/TableParser/ANSI-stripping care about: a colored
# banner, a y/n confirmation, a free-text prompt, a digit-percent progress
# bar (the exact shape that used to false-positive as a tcsh prompt), and a
# space-delimited table.

require 'io/console'
require_relative '../lib/rune/version'

$stdout.sync = true

CYAN = "\e[36m"
GREEN = "\e[32m"
YELLOW = "\e[33m"
BOLD = "\e[1m"
RESET = "\e[0m"

MENU = [
  { label: 'A table of fake data', action: :table },
  { label: 'A progress bar', action: :progress },
  { label: 'A yes/no confirmation', action: :confirm },
  { label: 'A free-text prompt', action: :ask_name },
  { label: 'Quit', action: :quit }
].freeze

def banner
  puts "#{BOLD}#{CYAN}rune demo TUI#{RESET}"
  puts "#{CYAN}A small interactive program for dogfooding rune run / rune watch.#{RESET}"
  puts
end

# Reads one logical keypress: a plain character, or a recognized arrow-key
# escape sequence (ESC [ A/B). `intr: true` keeps Ctrl+C generating a real
# Interrupt even while stdin is in raw mode for the read; the second/third
# bytes of an escape sequence use a short non-blocking timeout so a lone
# Escape key (not followed by a bracket sequence) returns instead of hanging.
def read_key
  first = $stdin.getch(intr: true)
  return first unless first == "\e"

  second = $stdin.getch(intr: true, min: 0, time: 0.5)
  return :escape unless second == '['

  case $stdin.getch(intr: true, min: 0, time: 0.5)
  when 'A' then :up
  when 'B' then :down
  else :unknown
  end
end

def render_menu(selected)
  MENU.each_with_index do |item, i|
    marker = i == selected ? "#{GREEN}❯#{RESET}" : ' '
    label = i == selected ? "#{BOLD}#{item[:label]}#{RESET}" : item[:label]
    print "\r\e[K#{marker} #{label}\r\n"
  end
end

def select_menu_action
  selected = 0
  puts "Use #{BOLD}↑/↓#{RESET} and #{BOLD}Enter#{RESET} to choose (or press q to quit):"
  render_menu(selected)
  loop do
    case read_key
    when :up
      print "\e[#{MENU.size}A"
      selected = (selected - 1) % MENU.size
      render_menu(selected)
    when :down
      print "\e[#{MENU.size}A"
      selected = (selected + 1) % MENU.size
      render_menu(selected)
    when "\r", "\n"
      return MENU[selected][:action]
    when 'q'
      return :quit
    end
  end
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
  case select_menu_action
  when :table then show_table
  when :progress then show_progress
  when :confirm then confirm
  when :ask_name then ask_name
  when :quit
    puts 'Goodbye!'
    break
  end
  puts
rescue Interrupt
  # Ctrl+C mid-prompt (e.g. while waiting on a keypress or `gets`) is a
  # normal way to end an interactive session, not a crash — exit quietly
  # instead of dumping a Ruby backtrace over whatever the human was doing.
  puts "\n#{YELLOW}Interrupted.#{RESET}"
  exit 130
end
