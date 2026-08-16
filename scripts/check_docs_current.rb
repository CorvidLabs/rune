#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/rune/version'
require 'json'
require 'open3'

# Fails when the guides have drifted from the CLI they describe.
#
# Both of these have happened more than once. A stale version string shipped in
# `docs/getting_started.md` through three releases, quoting `rune v0.2.1` while
# the gem was 0.7.0 — and it is the first thing a reader sees, so it undermines
# everything after it. Undocumented flags are worse than cosmetic: an agent
# following a guide that does not mention `--max-output` pages a whole
# transcript into its context believing no bound exists, which is exactly what
# one skill told agents to do for four releases.
#
# Deliberately narrow. This checks only what can be checked mechanically and
# without judgement: that version strings match, and that every flag the CLI
# advertises is named somewhere in the guides. Whether the prose is *correct* is
# a question for a reader, and no script should pretend otherwise.
module DocsCurrent
  GUIDES = ['README.md', 'docs/getting_started.md', 'docs/sessions.md', 'docs/pty_architecture.md'].freeze
  COMMANDS = %w[run watch session].freeze
  # `rune vX.Y.Z` in a console example, which is the shape that went stale.
  VERSION_MENTION = /\brune v(\d+\.\d+\.\d+)/

  module_function

  def guide_text
    @guide_text ||= GUIDES.filter_map { |path| File.read(path) if File.exist?(path) }.join("\n")
  end

  def stale_versions
    GUIDES.flat_map do |path|
      next [] unless File.exist?(path)

      File.readlines(path).each_with_index.filter_map do |line, index|
        found = line[VERSION_MENTION, 1]
        next if found.nil? || found == Rune::VERSION

        "#{path}:#{index + 1} says rune v#{found}, but Rune::VERSION is #{Rune::VERSION}"
      end
    end
  end

  def flags_for(command)
    stdout, _stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'bin/rune', command, '--help', '--json')
    return [] unless status.success?

    JSON.parse(stdout).dig('data', 'flags').to_a.map do |flag|
      flag['flag'].to_s.split('=').first.split(',').first.strip
    end
  rescue JSON::ParserError
    []
  end

  def undocumented_flags
    COMMANDS.flat_map do |command|
      flags_for(command).reject { |flag| guide_text.include?(flag) }
                        .map { |flag| "#{flag} is a `rune #{command}` flag and appears in no guide" }
    end
  end
end

require 'rbconfig'
problems = DocsCurrent.stale_versions + DocsCurrent.undocumented_flags

if problems.empty?
  puts "Guides are current with #{Rune::VERSION}"
else
  warn "Guides have drifted from the CLI:\n#{problems.map { |problem| "  - #{problem}" }.join("\n")}"
  exit 1
end
