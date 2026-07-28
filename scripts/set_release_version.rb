#!/usr/bin/env ruby
# frozen_string_literal: true

version = ARGV.first
unless version&.match?(/\A\d+\.\d+\.\d+\z/)
  warn 'Usage: fledge run set-version -- MAJOR.MINOR.PATCH'
  exit 1
end

root = File.expand_path('..', __dir__)
files = {
  File.join(root, 'lib/rune/version.rb') => [
    /(VERSION\s*=\s*['"])[^'"]+(['"])/,
    "\\1#{version}\\2"
  ],
  File.join(root, 'plugin.toml') => [
    /(\[plugin\].*?^\s*version\s*=\s*["'])[^"']+(["'])/m,
    "\\1#{version}\\2"
  ]
}

files.each do |path, (pattern, replacement)|
  content = File.read(path)
  updated = content.sub(pattern, replacement)
  raise "Could not update version in #{path}" if updated == content

  File.write(path, updated)
end

puts "Updated release versions to #{version}"
