#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/rune/version'

module ReleaseVersionCheck
  module_function

  def plugin_version
    plugin_toml = File.read(File.expand_path('../plugin.toml', __dir__))
    match = plugin_toml.match(/^\s*version\s*=\s*["']([^"']+)["']/)
    raise 'plugin.toml does not contain a version' unless match

    match[1]
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
