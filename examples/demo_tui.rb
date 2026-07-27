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

# Set RUNE_DEMO_DEBUG=1 to trace every getch call and its raw result — useful
# for diagnosing arrow-key/raw-input issues on a terminal/Ruby combination
# this wasn't tested against directly.
DEBUG = ENV['RUNE_DEMO_DEBUG'] == '1'

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
  return unless DEBUG

  io_console_version = Gem.loaded_specs['io-console']&.version || 'bundled with Ruby, no separate gem entry'
  puts "#{YELLOW}[debug] Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}), io-console: #{io_console_version}, " \
       "stdin.tty?=#{$stdin.tty?}#{RESET}"
  puts
end

def debug_log(msg)
  return unless DEBUG

  print "#{YELLOW}[debug] #{msg}#{RESET}\r\n"
end

# getch with intr: true (Ctrl+C still raises a real Interrupt during a raw
# read) and, optionally, a short non-blocking timeout. Falls back to plain
# getch if this Ruby/io-console combination doesn't accept these keywords
# together, rather than raising and silently killing the whole session.
def safe_getch(**opts)
  debug_log("calling getch(intr: true, #{opts}), stdin.tty?=#{$stdin.tty?}")
  result = $stdin.getch(intr: true, **opts)
  debug_log("getch returned #{result.inspect} (bytes: #{result&.bytes})")
  result
rescue ArgumentError => e
  debug_log("getch(intr:) rejected (#{e.message}), falling back to plain getch")
  result = $stdin.getch
  debug_log("plain getch returned #{result.inspect} (bytes: #{result&.bytes})")
  result
end

# Reads one logical keypress: a plain character, or a recognized arrow-key
# escape sequence. Terminals send one of two conventions for arrow keys
# depending on "cursor key mode" (DECCKM) — CSI (ESC [ A/B, the common
# default) or SS3 (ESC O A/B, "application mode", used by some terminals/
# configs) — both are accepted here since a spawned program can't control
# which one the far end of the pty actually sends. The second/third bytes
# use a short non-blocking timeout so a lone Escape key (not followed by
# either sequence) returns instead of hanging forever.
def read_key
  first = safe_getch
  return first unless first == "\e"

  second = safe_getch(min: 0, time: 0.5)
  return :escape unless ['[', 'O'].include?(second)

  case safe_getch(min: 0, time: 0.5)
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

def move_selection(selected, delta)
  print "\e[#{MENU.size}A"
  new_selected = (selected + delta) % MENU.size
  render_menu(new_selected)
  new_selected
end

def select_menu_action
  selected = 0
  puts "Use #{BOLD}↑/↓#{RESET} and #{BOLD}Enter#{RESET} to choose (or press q to quit):"
  render_menu(selected)
  loop do
    key = read_key
    debug_log("read_key -> #{key.inspect}")
    case key
    when :up then selected = move_selection(selected, -1)
    when :down then selected = move_selection(selected, 1)
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
rescue StandardError => e
  # A visible error beats a silent crash: without this, an exception in the
  # raw-mode read loop kills the process, raw mode gets released, and
  # whatever's left of the human's session just echoes literal keystrokes
  # back with no indication anything went wrong.
  puts "\n#{YELLOW}Unexpected error: #{e.class}: #{e.message}#{RESET}"
  exit 1
end
