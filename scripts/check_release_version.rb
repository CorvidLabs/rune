#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/rune/version'

module ReleaseVersionCheck
  PLUGIN_HEADER_PATTERN = /^\s*\[plugin\]\s*(?:#.*)?$/
  TABLE_HEADER_PATTERN = /^\s*\[{1,2}[^\]]+\]{1,2}\s*(?:#.*)?$/
  VERSION_PATTERN = /^\s*version\s*=\s*["']([^"']+)["'](?:\s*#.*)?\s*$/

  module_function

  def plugin_version
    plugin_toml = File.read(File.expand_path('../plugin.toml', __dir__))
    lines = plugin_toml.lines
    header_index = lines.index { |line| line.match?(PLUGIN_HEADER_PATTERN) }
    raise 'plugin.toml does not contain a [plugin] table' unless header_index

    table_end = ((header_index + 1)...lines.length).find do |index|
      lines[index].match?(TABLE_HEADER_PATTERN)
    end || lines.length
    matches = lines[(header_index + 1)...table_end].filter_map { |line| line.match(VERSION_PATTERN) }
    raise 'plugin.toml [plugin] table must contain exactly one version' unless matches.one?

    matches.first[1]
  end

  def normalize_expected_version(value)
    value&.delete_prefix('v')
  end

  def errors(expected_version)
    versions = {
      'lib/rune/version.rb' => Rune::VERSION,
      'plugin.toml' => plugin_version
    }
    expected = normalize_expected_version(expected_version)
    reference = expected || Rune::VERSION

    versions.filter_map do |source, version|
      "#{source} is #{version}, expected #{reference}" unless version == reference
    end
  end
end

errors = ReleaseVersionCheck.errors(ARGV.first)

if errors.empty?
  puts "Release versions agree at #{Rune::VERSION}"
else
  warn errors.join("\n")
  exit 1
end
