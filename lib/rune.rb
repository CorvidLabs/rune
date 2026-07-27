# frozen_string_literal: true

require_relative 'rune/version'
require_relative 'rune/result'
require_relative 'rune/renderer'
require_relative 'rune/command'
require_relative 'rune/cli'
require_relative 'rune/script'

# PTY Runner & Parsers
require_relative 'rune/parsers/text_sanitizer'
require_relative 'rune/parsers/table_parser'
require_relative 'rune/parsers/key_value_parser'
require_relative 'rune/pty_runner'

# Command implementations
require_relative 'rune/commands/version_command'
require_relative 'rune/commands/run_command'

module Rune
  class Error < StandardError; end
end
