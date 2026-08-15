#!/usr/bin/env ruby
# frozen_string_literal: true

# A stand-in agent REPL: prints a banner, prompts, thinks for a moment, then
# answers. It exists so you can exercise `rune session` — including `attach` —
# without spending API quota on a real agent CLI, and so the session examples
# have a target that behaves like one.
#
# Drive it the way an agent would:
#
#   rune session start --name demo -- ruby examples/humans/fake_agent.rb
#   rune session send  --name demo --settle-ms 800 "hello"
#   rune session list
#
# Then take the wheel yourself and give it back:
#
#   rune session attach --name demo      # type at it; Ctrl-] to detach
#   rune session stop   --name demo
#
# Or run it directly under a live passthrough:
#
#   rune watch -- ruby examples/humans/fake_agent.rb
#
# The deliberate pause before each reply is the point: it is what makes this a
# fair test of send-and-settle. A child that answers instantly would settle
# correctly even with a broken implementation, whereas one that echoes your
# input and *then* thinks is exactly what broke earlier versions.

THINK_SECONDS = Float(ENV['FAKE_AGENT_THINK'] || 1.2)

$stdout.sync = true

puts "\e[1mfake-agent\e[0m 1.0 — a stand-in for a real agent CLI"
puts "type something and press Enter; 'quit' to exit\n\n"

loop do
  print "\e[36m> \e[0m"
  line = $stdin.gets
  break if line.nil?

  request = line.strip
  next if request.empty?
  break if %w[quit exit].include?(request.downcase)

  # "Thinking" is rendered as a spinner so this also produces the kind of
  # repaint traffic a real TUI agent generates.
  spinner = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + THINK_SECONDS
  index = 0
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    print "\r\e[90m#{spinner[index % spinner.size]} thinking…\e[0m"
    index += 1
    sleep 0.08
  end
  print "\r\e[2K"

  puts "\e[32mreply:\e[0m #{request.reverse}"
  puts "\e[90m(#{request.length} chars, reversed)\e[0m"
end

puts "\nbye"
