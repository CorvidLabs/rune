#!/usr/bin/env ruby
# frozen_string_literal: true

# A CLI that asks the three kinds of question rune has to cope with: a yes/no
# confirmation, a hidden secret, and a numbered choice. It exists to exercise
# prompt detection and interactive input against realistic shapes.
#
# Watch it live and answer by hand:
#
#   rune watch -- ruby examples/humans/confirm_flow.rb
#
# Or script the answers and read the structured result:
#
#   printf 'y\nhunter2\n2\n' | rune run --json -- ruby examples/humans/confirm_flow.rb | jq .data
#
# Note what `prompt_detected` does here. It reports whether the *last* non-blank
# line looks like an interactive prompt, so it is `true` if you kill this
# mid-question and `false` once it has run to completion — "is it stuck waiting
# for me", not "did it ever ask anything". The shapes below (`[y/N]`,
# `Password:`) are exactly the ones rune recognizes; a real agent CLI's prompt
# usually is not, which is why sessions treat the field as advisory.

$stdout.sync = true

def ask(question)
  print question
  ($stdin.gets || '').strip
end

puts "\e[1mdeploy\e[0m — pre-flight questions\n\n"

confirm = ask('Deploy to production? [y/N] ')
unless confirm.downcase.start_with?('y')
  puts "\naborted; nothing was deployed"
  exit 0
end

# Echo is disabled the way a real credential prompt does it, so the secret does
# not land in the transcript rune records.
secret =
  begin
    require 'io/console'
    print 'Password: '
    value = $stdin.noecho(&:gets).to_s.strip
    puts
    value
  rescue LoadError, Errno::ENOTTY, IOError
    ask('Password: ')
  end

puts "\nSelect a region:"
regions = %w[us-east-1 eu-west-1 ap-southeast-2]
regions.each_with_index { |region, index| puts "  #{index + 1}. #{region}" }
choice = ask('Choice: ').to_i
region = regions[choice - 1] || regions.first

puts "\n\e[32m✓\e[0m deploying to \e[1m#{region}\e[0m"
puts "  credential length: #{secret.length} (never printed)"
puts 'done'
