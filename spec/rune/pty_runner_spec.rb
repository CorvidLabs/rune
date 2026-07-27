# frozen_string_literal: true

require 'spec_helper'
require 'rune/script'
require 'tmpdir'

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

    it 'handles wrapped commands emitting bytes that are not valid UTF-8 without crashing' do
      # printf interprets the \xHH escapes itself, emitting raw invalid-UTF-8
      # bytes on stdout — this is what a real command (e.g. a compiler
      # emitting non-UTF-8 diagnostic bytes) looks like from PTYRunner's side.
      runner = described_class.new(['printf', '\xff\xfe\x00binary garbage\n'])
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      expect(result.data[:clean_output]).to include('binary garbage')
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

    it 'reports permission-denied (a non-executable file) as exit code 126, not a crash' do
      Dir.mktmpdir do |dir|
        script_path = File.join(dir, 'not_executable.sh')
        File.write(script_path, "#!/bin/sh\necho hi\n")
        File.chmod(0o644, script_path)

        result = described_class.new(script_path).run

        expect(result).to be_success
        expect(result.data[:exit_code]).to eq(126)
        expect(result.data[:clean_output]).to include('Permission denied')
      end
    end

    it 'times out and reports it in both the output and exit code, without hanging past the limit' do
      runner = described_class.new('sleep 5', timeout_seconds: 1)

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = runner.run
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(elapsed).to be < 3
      expect(result.data[:exit_code]).to eq(124)
      expect(result.data[:clean_output]).to include('[rune] Execution timed out after 1 seconds')
    end

    it 'wraps any other unexpected error in a generic failure instead of propagating it raw' do
      allow(PTY).to receive(:spawn).and_raise(RuntimeError, 'something truly unexpected')

      result = described_class.new('echo hi').run

      expect(result).to be_failure
      expect(result.error).to include("Failed to execute command 'echo hi'").and include('something truly unexpected')
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

    it 'honors a :pause script step, waiting at least that long before sending the next step' do
      ruby_code = <<~RUBY
        $stdout.sync = true
        puts "Ready"
        line = $stdin.gets&.strip
        puts "Got \#{line}"
      RUBY

      script = Rune::Script.new do
        wait_for(/Ready/)
        pause 0.3
        send_keys "go\n"
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = described_class.new(['ruby', '-e', ruby_code], script: script).run
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(result).to be_success
      expect(result.data[:clean_output]).to include('Got go')
      expect(elapsed).to be >= 0.3
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

  describe '#write_input (private, exercised directly)' do
    it 'swallows a write failure instead of raising, e.g. writing to an already-closed pty' do
      broken_writer = instance_double(IO, wait_writable: true)
      allow(broken_writer).to receive(:write_nonblock).and_raise(Errno::EPIPE, 'broken pipe')

      runner = described_class.new('echo hi')
      expect { runner.send(:write_input, broken_writer, "data\n") }.not_to raise_error
    end

    it 'is a no-op for nil or empty data' do
      writer = instance_double(IO, wait_writable: true)
      runner = described_class.new('echo hi')

      runner.send(:write_input, writer, nil)
      runner.send(:write_input, writer, '')

      expect(writer).not_to have_received(:wait_writable)
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
