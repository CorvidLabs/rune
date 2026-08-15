# frozen_string_literal: true

require_relative 'rune/version'
require_relative 'rune/result'
require_relative 'rune/renderer'
require_relative 'rune/help'
require_relative 'rune/command'
require_relative 'rune/cli'
require_relative 'rune/script'

# PTY Runner & Parsers
require_relative 'rune/parsers/text_sanitizer'
require_relative 'rune/parsers/prompt_detector'
require_relative 'rune/parsers/table_parser'
require_relative 'rune/parsers/key_value_parser'
require_relative 'rune/signal_handler'
require_relative 'rune/utf8_stream_decoder'
require_relative 'rune/pty_runner'
require_relative 'rune/pty_watcher'

# Persistent named sessions
require_relative 'rune/output_limiter'
require_relative 'rune/session/prompt_scanner'
require_relative 'rune/session/store'
require_relative 'rune/session/client'
require_relative 'rune/session/supervisor'
require_relative 'rune/session/attachment'

# Command implementations
require_relative 'rune/commands/version_command'
require_relative 'rune/commands/run_command'
require_relative 'rune/commands/watch_command'
require_relative 'rune/commands/session_command'

module Rune
  class Error < StandardError; end
end
