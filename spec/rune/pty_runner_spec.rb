# frozen_string_literal: true

require 'spec_helper'
require 'rune/script'

RSpec.describe Rune::PTYRunner do
  describe '#run' do
    it 'executes command and captures clean output and exit code' do
      runner = described_class.new('echo "Hello World"')
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      expect(result.data[:clean_output]).to include('Hello World')
      expect(result.data[:duration_ms]).to be_a(Numeric)
    end

    it 'captures non-zero exit codes' do
      runner = described_class.new('ruby -e "exit 42"')
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(42)
    end

    it "mirrors the wrapped command's exit code as the process-level Result#exit_code, " \
       'so callers composing with shell && / || / set -e see it, even though the Result itself succeeded' do
      runner = described_class.new('ruby -e "exit 42"')
      result = runner.run

      expect(result).to be_success
      expect(result.exit_code).to eq(42)
    end

    it 'handles array command arguments with shell escaping' do
      runner = described_class.new(['ruby', '-e', 'puts ARGV[0]', 'hello world'])
      result = runner.run

      expect(result).to be_success
      expect(result.data[:clean_output]).to include('hello world')
    end

    it 'fails gracefully instead of crashing when the pty stdlib is unavailable' do
      allow(described_class).to receive(:pty_available?).and_return(false)

      result = described_class.new('echo hi').run

      expect(result).to be_failure
      expect(result.error).to include('PTY unavailable')
    end

    it 'fails gracefully instead of crashing when the OS refuses to allocate a pty at runtime' do
      allow(PTY).to receive(:spawn).and_raise(Errno::ENXIO, 'no ptys available')

      result = described_class.new('echo hi').run

      expect(result).to be_failure
      expect(result.error).to include('PTY allocation failed at runtime')
    end

    it 'still treats Errno::ENOENT/EACCES as a property of the wrapped command, not the platform' do
      result = described_class.new('non_existent_command_xyz_12345').run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(127)
    end

    it 'handles missing commands gracefully with exit code 127' do
      runner = described_class.new('non_existent_command_xyz_12345')
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(127)
      expect(result.data[:clean_output]).to include('Command not found')
    end

    it 'executes interactive script DSL steps inside PTY' do
      ruby_code = <<~RUBY
        $stdout.sync = true
        puts "Select an option [1-3]:"
        line = $stdin.gets&.strip
        puts "You selected \#{line}"
      RUBY

      script = Rune::Script.define do
        wait_for(/Select an option/)
        send_keys "2\n"
      end

      runner = described_class.new(['ruby', '-e', ruby_code], script: script)
      result = runner.run

      expect(result).to be_success
      expect(result.data[:clean_output]).to include('You selected 2')
    end

    it 'drives a script built with Script.new directly (not only .define)' do
      ruby_code = <<~RUBY
        $stdout.sync = true
        puts "Select an option [1-3]:"
        line = $stdin.gets&.strip
        puts "You selected \#{line}"
      RUBY

      script = Rune::Script.new do
        wait_for(/Select an option/)
        send_keys "3\n"
      end

      runner = described_class.new(['ruby', '-e', ruby_code], script: script)
      result = runner.run

      expect(result).to be_success
      expect(result.data[:clean_output]).to include('You selected 3')
    end

    it 'forwards SIGINT to the wrapped child process, terminating it early' do
      runner = described_class.new('sleep 10', timeout_seconds: 30)

      Thread.new do
        sleep 0.3
        Process.kill('INT', Process.pid)
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = runner.run
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(result).to be_success
      expect(elapsed).to be < 5
      expect(result.data[:exit_code]).to eq(130)
    end
  end

  describe '#detect_prompt?' do
    let(:runner) { described_class.new('echo test') }

    it 'detects real shell prompts and interactive questions' do
      expect(runner.detect_prompt?('user@hostname:~$ ')).to be true
      expect(runner.detect_prompt?('bash-5.2# ')).to be true
      expect(runner.detect_prompt?('➜  rune git:(main) ')).to be true
      expect(runner.detect_prompt?('? Select target environment: ')).to be true
      expect(runner.detect_prompt?('Do you want to proceed? [y/N] ')).to be true
      expect(runner.detect_prompt?('Password: ')).to be true
    end

    it 'ignores false positives like code snippets or text with angle brackets/dollars' do
      expect(runner.detect_prompt?('  > This is a blockquote')).to be false
      expect(runner.detect_prompt?('if (x > 5) { return true; }')).to be false
      expect(runner.detect_prompt?('export PATH=$PATH:/usr/bin')).to be false
      expect(runner.detect_prompt?('# Section 1 Header')).to be false
    end

    it 'ignores digit-percent progress output, not just tcsh-style prompts ending in %' do
      expect(runner.detect_prompt?('Building... 45%')).to be false
      expect(runner.detect_prompt?('Downloading 100%')).to be false
      expect(runner.detect_prompt?('Progress: 3.5%')).to be false
    end
  end
end
