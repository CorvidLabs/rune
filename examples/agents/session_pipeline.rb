#!/usr/bin/env ruby
# frozen_string_literal: true

# One agent driving another through a persistent `rune session`.
#
# This is the shape `rune session` exists for: start a REPL-style child once,
# hold a conversation with it across several turns, then shut it down — all
# from a program, with no human at the keyboard.
#
#   ruby examples/agents/session_pipeline.rb
#
# Drives `bash` by default so it runs anywhere with no API keys. Point it at a
# real agent CLI to see the actual use case:
#
#   RUNE_SESSION_CMD=grok   ruby examples/agents/session_pipeline.rb
#   RUNE_SESSION_CMD=claude ruby examples/agents/session_pipeline.rb
#
# A real agent CLI needs a longer settle window than a shell, because it thinks
# before it answers:
#
#   RUNE_SESSION_CMD=grok RUNE_SETTLE_MS=4000 ruby examples/agents/session_pipeline.rb

require 'json'
require 'tmpdir'
require_relative '../../lib/rune'

COMMAND = (ENV['RUNE_SESSION_CMD'] || 'bash --norc -i').split
SETTLE_MS = Integer(ENV['RUNE_SETTLE_MS'] || 600)
PROMPTS = if ENV['RUNE_SESSION_CMD']
            ['reply with exactly: PONG', 'now reply with exactly: DONE']
          else
            ['MEMORY=persisted', 'echo "value=$MEMORY"']
          end.freeze

def session(*args)
  Rune::Commands::SessionCommand.new.call(args.map(&:to_s), {})
end

def report(label, result)
  if result.failure?
    warn "#{label}: FAILED — #{result.error}"
    exit 1
  end
  result
end

# Sessions are keyed by RUNE_HOME; a temp one keeps this example from touching
# whatever real sessions you have open.
Dir.mktmpdir('rune-example') do |home|
  ENV['RUNE_HOME'] = home

  # 1. Start. `--name` is optional — rune generates a `<tool>-<word>` codename,
  #    which is what keeps "the grok session" unambiguous once there are two.
  started = report('start', session('start', '--', *COMMAND))
  name = started.data[:name]
  puts "started session #{name.inspect} running #{COMMAND.join(' ')} (pid #{started.data[:child_pid]})"

  # 2. Converse. Each send returns *only* what that send produced, so the reply
  #    can be handed straight to whatever decides the next prompt.
  PROMPTS.each_with_index do |prompt, index|
    puts "\n--- turn #{index + 1}: #{prompt}"
    reply = report('send', session('send', "--name=#{name}", "--settle-ms=#{SETTLE_MS}",
                                   '--timeout-ms=120000', '--', prompt))
    puts "settled=#{reply.data[:settled]} timed_out=#{reply.data[:timed_out].inspect}"
    # clean_output is the ANSI-stripped view; output keeps the raw bytes.
    puts reply.data[:clean_output].to_s.lines.map { |line| "    #{line.chomp}" }.join("\n")
  end

  # 3. Inspect the fleet the way a supervising agent would: state, how long each
  #    session has been quiet, and the last thing it printed.
  puts "\n--- session list"
  session('list').data[:sessions].each do |entry|
    puts format('    %<name>-16s %<state>-9s idle=%<idle>-7s %<last>s',
                name: entry[:name], state: entry[:state],
                idle: "#{entry[:idle_ms]}ms", last: entry[:last_line])
  end

  # 4. Stop. `stop` is idempotent and waits for the processes to actually go
  #    away, so nothing is left running behind this script.
  report('stop', session('stop', "--name=#{name}"))
  puts "\nstopped #{name.inspect}"
end
