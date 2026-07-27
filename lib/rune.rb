# frozen_string_literal: true

require_relative 'rune/version'
require_relative 'rune/result'
require_relative 'rune/renderer'
require_relative 'rune/command'
require_relative 'rune/cli'

# Command implementations
require_relative 'rune/commands/version_command'

module Rune
  class Error < StandardError; end
end
