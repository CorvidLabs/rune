#!/usr/bin/env ruby
# frozen_string_literal: true

# Ask several agents the same question and compare their answers.
#
#   ruby examples/agents/multi_agent_fanout.rb
#
# This is the orchestration shape sessions exist to support: one process holds
# several named children open at once, addresses each by name, and collects
# structured replies. rune is the broker — deciding who to ask and what to do
# with the answers stays here, in the caller.
#
# Defaults to three shells so it runs anywhere. Point it at real agent CLIs:
#
#   RUNE_FANOUT="grok,claude,codex" RUNE_SETTLE_MS=4000 \
#     ruby examples/agents/multi_agent_fanout.rb
#
# Note the sends are sequential, not concurrent. A single session serializes
# work by design (one in-flight send at a time), and driving several *different*
# sessions concurrently would need threads — deliberately left out so the
# example stays about the session API rather than about Ruby concurrency.

require 'tmpdir'
require_relative '../../lib/rune'

TARGETS = (ENV['RUNE_FANOUT'] || 'bash --norc -i,bash --norc -i,bash --norc -i').split(',').map(&:strip)
SETTLE_MS = Integer(ENV['RUNE_SETTLE_MS'] || 600)
DEFAULT_QUESTION = ENV['RUNE_FANOUT'] ? 'In one short sentence: what is a pseudo-terminal?' : 'uname -s'
QUESTION = ENV['RUNE_QUESTION'] || DEFAULT_QUESTION

def session(*args)
  Rune::Commands::SessionCommand.new.call(args.map(&:to_s), {})
end

# 1. Start one session per target. Omitting --name lets rune generate a distinct
#    <tool>-<word> codename for each, which is what keeps two sessions of the
#    *same* tool tellable apart.
def start_all
  TARGETS.filter_map do |target|
    started = session('start', '--', *target.split)
    if started.failure?
      warn "  skip #{target}: #{started.error}"
      next
    end
    puts "started #{started.data[:name]} -> #{target}"
    started.data[:name]
  end
end

def ask(name)
  reply = session('send', "--name=#{name}", "--settle-ms=#{SETTLE_MS}", '--timeout-ms=180000', '--', QUESTION)
  text = reply.success? ? reply.data[:clean_output].to_s : "ERROR: #{reply.error}"
  { name: name, settled: reply.success? && reply.data[:settled], text: text }
end

def render(answer)
  puts "\e[1m#{answer[:name]}\e[0m (settled=#{answer[:settled]})"
  # The echoed prompt is included in a reply on purpose — silently dropping data
  # would be worse — but a side-by-side comparison wants it out.
  body = answer[:text].lines.reject { |line| line.strip == QUESTION.strip }
  puts body.map { |line| "    #{line.chomp}" }.join("\n")
  puts
end

Dir.mktmpdir('rune-fanout') do |home|
  ENV['RUNE_HOME'] = home
  names = start_all
  abort 'no sessions started' if names.empty?

  puts "\nasking all #{names.size}: #{QUESTION.inspect}\n\n"
  names.map { |name| ask(name) }.each { |answer| render(answer) }

  names.each { |name| session('stop', "--name=#{name}") }
  puts "stopped #{names.size} session(s)"
end
