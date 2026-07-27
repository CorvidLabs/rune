# frozen_string_literal: true

require_relative 'xzst/version'
require_relative 'xzst/result'
require_relative 'xzst/renderer'
require_relative 'xzst/command'
require_relative 'xzst/cli'

# Command implementations
require_relative 'xzst/commands/version_command'

module XZST
  class Error < StandardError; end
end
