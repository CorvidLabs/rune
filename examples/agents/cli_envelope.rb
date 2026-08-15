#!/usr/bin/env ruby
# frozen_string_literal: true

# Driving rune as a subprocess, without loading the library.
#
#   ruby examples/agents/cli_envelope.rb
#
# Note what this file does *not* do: there is no `require_relative '../../lib/rune'`
# anywhere below. Everything here goes through the `rune` executable and reads
# the JSON envelope it prints, which is the integration path for anything that
# shells out rather than depending on the gem — another language, a sandboxed
# runner, or an agent that only knows how to run commands.
#
# The envelope *is* the API. Every command returns the same
# `{"status": ..., "data": ...}` shape on stdout, so the only parsing anyone
# needs is `JSON.parse`.

require 'json'
require 'open3'

RUNE = File.expand_path('../../bin/rune', __dir__)

def heading(text) = puts("\n\e[1m#{text}\e[0m")

# Every call returns [parsed_envelope, process_status]. `--json` is passed for
# clarity, though rune switches to structured output on its own whenever stdout
# is not a terminal.
#
# Note where --json is inserted: *before* the `--` separator. Appending it to
# the end instead hands it to the wrapped command, which is exactly the mistake
# section 2 below is about — `git log --json` fails, and rune never sees the
# flag at all. Writing this example wrong first is how that comment got here.
def rune(*args)
  separator = args.index('--')
  argv = separator ? args[0...separator] + ['--json'] + args[separator..] : args + ['--json']
  stdout, _stderr, status = Open3.capture3({ 'RUNE_HOME' => ENV.fetch('RUNE_HOME') }, RUNE, *argv)
  [JSON.parse(stdout, symbolize_names: true), status]
rescue JSON::ParserError => e
  abort "rune #{argv.join(' ')}: stdout was not JSON (#{e.message})"
end

require 'tmpdir'

def envelope_is_the_api
  heading('1. the envelope is the API')
  envelope, = rune('run', '--', 'git', 'log', '--oneline', '-1')
  puts "  status=#{envelope[:status]} exit_code=#{envelope[:data][:exit_code]}"
  puts "  #{envelope[:data][:clean_output].to_s.chomp}"
end

def separator_protects_the_child
  heading('2. `--` is what protects the wrapped command')
  # Without the separator rune would consume --json itself and git would never
  # see its own flags.
  sha, = rune('run', '--', 'git', 'log', '--pretty=format:%H', '-1')
  puts "  git's own --pretty survived: #{sha[:data][:clean_output].to_s[0, 12]}"
end

def exit_status_composes
  heading('3. exit status composes, even though the Result is a success')
  failing, status = rune('run', '--', 'false')
  puts "  envelope status=#{failing[:status]} (a Result, not an exception)"
  puts "  process exitstatus=#{status.exitstatus} — so shell-style control flow still works"
end

def bounded_output
  heading('4. bound output you did not write')
  bounded, = rune('run', '--tail=2', '--', 'seq', '1', '500')
  puts "  truncated=#{bounded[:data][:truncated]} omitted_lines=#{bounded[:data][:omitted_lines]}"
  puts "  kept: #{bounded[:data][:clean_output].to_s.lines.map(&:chomp).join(', ')}"
end

def discoverable_surface
  heading('5. discover the surface without scraping help text')
  help, = rune('session', '--help')
  help[:data][:flags].first(4).each { |flag| puts "  #{flag[:flag]}" }
end

def whole_session
  heading('6. a whole session conversation, as subprocesses')
  started, = rune('session', 'start', '--', 'bash', '--norc', '-i')
  name = started[:data][:name]
  puts "  started session: #{name}"

  puts "  answer: #{ask(name, 'X=41; echo $((X+1))')}"
  report_sessions
  stopped, = rune('session', 'stop', "--name=#{name}")
  puts "  stopped: #{stopped[:data][:state]}"
end

def ask(name, text)
  reply, = rune('session', 'send', "--name=#{name}", '--settle-ms=400', '--timeout-ms=20000', '--', text)
  reply[:data][:clean_output].to_s.lines.map(&:chomp).find { |line| line.match?(/\A\d+\z/) }
end

def report_sessions
  listing, = rune('session', 'list')
  listing[:data][:sessions].each { |entry| puts "  #{entry[:name]}  #{entry[:state]}  idle=#{entry[:idle_ms]}ms" }
end

def structured_failures
  heading('7. failures are structured too')
  missing, = rune('session', 'send', '--name=no-such-session', '--', 'hello')
  puts "  status=#{missing[:status]}"
  puts "  error=#{missing[:error]}"
end

Dir.mktmpdir('rune-cli-example') do |home|
  ENV['RUNE_HOME'] = home
  envelope_is_the_api
  separator_protects_the_child
  exit_status_composes
  bounded_output
  discoverable_surface
  whole_session
  structured_failures
end
