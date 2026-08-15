#!/usr/bin/env ruby
# frozen_string_literal: true

# How to drive an agent that misbehaves — which, in practice, is all of them.
#
#   ruby examples/agents/resilient_send.rb
#
# Every case below is one that actually happened while dogfooding rune against
# real agent CLIs, so this doubles as the list of failure modes worth handling:
#
#   1. The child is slow to boot, so a send fired straight after `start` is lost.
#   2. The child never answers, and the send hits `--timeout-ms`.
#   3. The child exits mid-conversation (crash, quota, /quit).
#   4. The reply arrives, but only a known marker tells you it is complete.
#
# The rule that ties them together: a driven agent failing is *data*, not an
# exception. `send` returns `settled`/`timed_out` on a normal Result, so the
# caller decides what to do rather than being unwound.

require 'tmpdir'
require_relative '../../lib/rune'

def session(*args)
  Rune::Commands::SessionCommand.new.call(args.map(&:to_s), {})
end

def heading(text) = puts("\n\e[1m#{text}\e[0m")

# `start` returns once the *supervisor* is up, which is necessarily before an
# arbitrary child has booted. Anything sent before the child is listening is
# lost, so wait for a marker you expect rather than assuming readiness.
def await_marker(name, marker, timeout: 10)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  until session('read', "--name=#{name}").data[:output].to_s.include?(marker)
    raise "#{name}: never saw #{marker.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    sleep 0.05
  end
end

# Single-quoted heredocs: the `#{...}` below belongs to the *child* program, so
# it must survive this file unevaluated.
SLOW_BOOT = <<~'RUBY'
  sleep 0.6
  STDOUT.sync = true
  puts 'READY'
  while (line = STDIN.gets)
    puts "ok:#{line.strip}"
  end
RUBY

MUTE = <<~RUBY
  STDOUT.sync = true
  puts 'READY'
  sleep 300
RUBY

QUITTER = <<~RUBY
  STDOUT.sync = true
  puts 'READY'
  STDIN.gets
  exit 3
RUBY

CHATTY = <<~'RUBY'
  STDOUT.sync = true
  puts 'READY'
  while STDIN.gets
    5.times { |i| puts "chunk #{i}"; sleep 0.2 }
    puts '<<END>>'
  end
RUBY

def slow_boot_case
  heading('1. waiting for the child to actually be ready')
  session('start', '--name=slowboot', '--', 'ruby', '-e', SLOW_BOOT)
  await_marker('slowboot', 'READY')
  puts '  child announced READY; safe to send'
  reply = session('send', '--name=slowboot', '--settle-ms=300', '--timeout-ms=15000', '--', 'hello')
  puts "  reply: #{reply.data[:clean_output].to_s.lines.last.to_s.chomp}"
  session('stop', '--name=slowboot')
end

def timeout_case
  heading('2. handling a child that never answers')
  session('start', '--name=mute', '--', 'ruby', '-e', MUTE)
  # Lesson 1 again, and it bites even here: without waiting, the banner lands
  # *after* this send's cursor and counts as its reply, so the call settles on
  # the banner instead of timing out.
  await_marker('mute', 'READY')
  reply = session('send', '--name=mute', '--settle-ms=300', '--timeout-ms=1500', '--', 'are you there?')
  puts "  settled=#{reply.data[:settled]} timed_out=#{reply.data[:timed_out]}"
  puts '  caller decides: retry, escalate, or give up. Nothing was raised.'
  session('stop', '--name=mute')
end

def exited_child_case
  heading('3. detecting a child that exited mid-conversation')
  session('start', '--name=quitter', '--', 'ruby', '-e', QUITTER)
  await_marker('quitter', 'READY')
  session('send', '--name=quitter', '--settle-ms=300', '--timeout-ms=10000', '--', 'goodbye')
  sleep 0.4
  report_exit('quitter')
end

def report_exit(name)
  entry = session('list').data[:sessions].find { |candidate| candidate[:name] == name }
  puts "  state=#{entry[:state]} exit_code=#{entry[:exit_code].inspect}"
  followup = session('send', "--name=#{name}", '--settle-ms=300', '--timeout-ms=5000', '--', 'still there?')
  puts "  follow-up failed cleanly: #{followup.error}" if followup.failure?
  # Whatever it said before dying is still readable from the transcript.
  puts "  transcript survives: #{session('read', "--name=#{name}").data[:clean_output].to_s.strip.inspect}"
end

def marker_case
  heading('4. --wait-for-regex beats guessing at a settle window')
  session('start', '--name=chatty', '--', 'ruby', '-e', CHATTY)
  await_marker('chatty', 'READY')
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  marked = session('send', '--name=chatty', '--settle-ms=30000', '--timeout-ms=20000',
                   '--wait-for-regex=<<END>>', '--', 'go')
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
  puts "  matched=#{marked.data[:matched]} in #{elapsed}s despite a 30s settle window"
  session('stop', '--name=chatty')
end

Dir.mktmpdir('rune-resilient') do |home|
  ENV['RUNE_HOME'] = home
  slow_boot_case
  timeout_case
  exited_child_case
  marker_case
  puts "\nall four failure modes handled without a single exception"
end
