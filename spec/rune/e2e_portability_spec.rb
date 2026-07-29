# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'rune binary E2E portability' do
  let(:e2e_spec) { File.expand_path('e2e_spec.rb', __dir__) }

  it 'loads and runs non-PTY examples when the pty extension is unavailable' do
    Dir.mktmpdir do |load_path|
      File.write(File.join(load_path, 'pty.rb'), "raise LoadError, 'simulated missing pty extension'\n")
      rubyopt = [ENV.fetch('RUBYOPT', nil), "-I#{load_path}"].compact.join(' ')
      environment = { 'COVERAGE' => nil, 'RUBYOPT' => rubyopt }

      output, status = Open3.capture2e(
        environment,
        'bundle',
        'exec',
        'rspec',
        e2e_spec,
        '--format',
        'progress'
      )

      expect(status).to be_success, output
      expect(output).to match(/9 examples, 0 failures, 5 pending/)
    end
  end
end
