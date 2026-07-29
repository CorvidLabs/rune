#!/usr/bin/env ruby
# frozen_string_literal: true

version = ARGV.first
unless version&.match?(/\A\d+\.\d+\.\d+\z/)
  warn 'Usage: fledge run set-version -- MAJOR.MINOR.PATCH'
  exit 1
end

root = File.expand_path('..', __dir__)
plugin_header_pattern = /^\s*\[plugin\]\s*(?:#.*)?$/
table_header_pattern = /^\s*\[{1,2}[^\]]+\]{1,2}\s*(?:#.*)?$/
plugin_version_pattern = /^(\s*version\s*=\s*["'])[^"']+(["'](?:\s*#.*)?\s*)$/

version_path = File.join(root, 'lib/rune/version.rb')
version_content = File.read(version_path)
version_pattern = /(VERSION\s*=\s*['"])[^'"]+(['"])/
raise "Could not update version in #{version_path}" unless version_content.match?(version_pattern)

plugin_path = File.join(root, 'plugin.toml')
plugin_lines = File.read(plugin_path).lines
plugin_header_index = plugin_lines.index { |line| line.match?(plugin_header_pattern) }
raise "Could not find [plugin] table in #{plugin_path}" unless plugin_header_index

plugin_table_end = ((plugin_header_index + 1)...plugin_lines.length).find do |index|
  plugin_lines[index].match?(table_header_pattern)
end || plugin_lines.length
plugin_version_indices = ((plugin_header_index + 1)...plugin_table_end).select do |index|
  plugin_lines[index].match?(plugin_version_pattern)
end
raise "Expected exactly one version in [plugin] table in #{plugin_path}" unless plugin_version_indices.one?

plugin_version_index = plugin_version_indices.first
plugin_lines[plugin_version_index] = plugin_lines[plugin_version_index].sub(
  plugin_version_pattern,
  "\\1#{version}\\2"
)

File.write(version_path, version_content.sub(version_pattern, "\\1#{version}\\2"))
File.write(plugin_path, plugin_lines.join)

puts "Updated release versions to #{version}"
