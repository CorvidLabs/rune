# frozen_string_literal: true

require 'xzst'
require 'json'
require 'stringio'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

# Helper: capture CLI output
def capture_cli(*argv, json: false)
  io = StringIO.new
  args = argv.flatten
  args << '--json' if json
  begin
    XZST::CLI.new(io:).run(args)
  rescue SystemExit
    # expected — CLI calls exit
  end
  io.string
end

# Helper: parse JSON output from agent mode
def cli_json(*argv)
  JSON.parse(capture_cli(*argv, json: true), symbolize_names: true)
end
