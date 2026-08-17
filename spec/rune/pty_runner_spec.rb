# frozen_string_literal: true

require 'spec_helper'
require 'rune/script'
require 'timeout'
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

    it 'does not misreport prompt_detected on a command that already exited cleanly, just ' \
       'because some line of its output ends in a <placeholder> example (found via real ' \
       'dogfooding: `rune run --json -- fledge plugins search rune` misreported this on its ' \
       "closing 'Install with: fledge plugins install <owner/repo>' line)" do
      runner = described_class.new(['ruby', '-e', 'puts "Install with: fledge plugins install <owner/repo>"'])
      result = runner.run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(0)
      expect(result.data[:prompt_detected]).to be false
    end

    it 'does not misreport prompt_detected when a prompt-shaped line appears mid-run and is ' \
       'followed by more real output (issue #30: a long TUI-heavy session almost always has ' \
       'SOME line that looks prompt-shaped as ordinary chrome; only the truly last line matters)' do
      ruby_code = 'puts "user@host:~$ "; puts "still working"; puts "done"'
      result = described_class.new(['ruby', '-e', ruby_code]).run

      expect(result).to be_success
      expect(result.data[:clean_output]).to include('still working').and include('done')
      expect(result.data[:prompt_detected]).to be false
    end

    it 'reports prompt_detected: true when the last non-blank line of output is genuinely ' \
       'prompt-shaped, with nothing after it' do
      result = described_class.new(['ruby', '-e', 'puts "Password: "']).run

      expect(result).to be_success
      expect(result.data[:prompt_detected]).to be true
    end

    it 'reports prompt_detected: false for a command with no output at all' do
      result = described_class.new('true').run

      expect(result).to be_success
      expect(result.data[:prompt_detected]).to be false
    end

    it 'reports prompt_detected: true for a --timeout kill whose last on-screen line was a ' \
       'prompt (previously hardcoded false on every timeout regardless of actual content, since ' \
       'the old per-chunk accumulator never received its final value once Timeout::Error ' \
       'interrupted execution before that assignment completed)' do
      # timeout_seconds: 3, not 1 — under real system load a `ruby -e` child's own interpreter
      # boot time can stretch enough to approach a 1s timeout, racing the "Password: " print
      # against the kill and turning this into a test-only flake rather than exercising the fix
      # under test (same reasoning as the orphan-process timeout test above).
      runner = described_class.new(['ruby', '-e', 'puts "Password: "; sleep 10'], timeout_seconds: 3)
      result = runner.run

      expect(result.data[:exit_code]).to eq(124)
      expect(result.data[:prompt_detected]).to be true
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
      command = ['ruby', '-e', 'puts ARGV[0]', 'hello world']
      expect(PTY).to receive(:spawn).with(
        { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' },
        *command
      ).and_call_original
      runner = described_class.new(command)
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

    it 'kills the timed-out child process instead of leaving it running as an orphan (found ' \
       'via a real `ps aux` check after `rune run --timeout=1 -- sleep 30` — Timeout.timeout ' \
       'only interrupts rune\'s own control flow, not the spawned OS process)' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'pid')
        # timeout_seconds: 3, not 1 — under real system load (many parallel
        # subprocesses/coverage instrumentation, observed directly during
        # this project's own dogfooding) a `ruby -e` child's own interpreter
        # boot time can stretch enough to approach a 1s timeout, racing the
        # pid-capture callback before Timeout fires and turning this into a
        # test-only flake rather than exercising the fix under test.
        runner = described_class.new(['ruby', '-e', "File.write(#{pid_file.inspect}, Process.pid); sleep 10"],
                                     timeout_seconds: 3)

        result = runner.run
        child_pid = File.read(pid_file).strip.to_i
        sleep 0.2 # give the OS a moment to finish tearing down the killed process

        expect(result.data[:exit_code]).to eq(124)
        expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
      end
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

    it 'does not add truncated/omitted_* keys to the result data when neither option is set ' \
       '(regression guard: the default result data shape must stay byte-for-byte unchanged)' do
      result = described_class.new('echo hi').run

      expect(result.data).not_to have_key(:truncated)
      expect(result.data).not_to have_key(:omitted_bytes)
      expect(result.data).not_to have_key(:omitted_lines)
    end

    it 'bounds clean_output/raw_output to max_output_bytes, keeping head and tail' do
      runner = described_class.new(['ruby', '-e', 'print "a" * 5000'], max_output_bytes: 200)
      result = runner.run

      expect(result).to be_success
      expect(result.data[:clean_output].bytesize).to be <= 200
      expect(result.data[:raw_output].bytesize).to be <= 200
      expect(result.data[:truncated]).to be true
      expect(result.data[:omitted_bytes]).to be > 0
    end

    it 'leaves output untouched when max_output_bytes is larger than the actual output' do
      runner = described_class.new('echo hi', max_output_bytes: 1_000_000)
      result = runner.run

      expect(result.data[:clean_output]).to include('hi')
      expect(result.data[:truncated]).to be false
      expect(result.data[:omitted_bytes]).to eq(0)
    end

    it 'bounds clean_output/raw_output to the last tail_lines lines' do
      runner = described_class.new(['ruby', '-e', '30.times { |i| puts i }'], tail_lines: 5)
      result = runner.run

      expect(result).to be_success
      kept = result.data[:clean_output].split("\n")
      expect(kept).to eq(%w[25 26 27 28 29])
      expect(result.data[:truncated]).to be true
      expect(result.data[:omitted_lines]).to eq(25)
    end

    it 'separates stdout and stderr into clean_stdout/clean_stderr when separate_streams is true, ' \
       'while still returning the existing merged clean_output/raw_output view' do
      runner = described_class.new(['bash', '-c', 'echo out1; echo err1 >&2; echo out2; echo err2 >&2'],
                                   separate_streams: true)
      result = runner.run

      expect(result).to be_success
      expect(result.data[:clean_stdout]).to eq("out1\nout2\n")
      expect(result.data[:clean_stderr]).to eq("err1\nerr2\n")
      expect(result.data[:clean_output]).to include('out1').and include('out2')
        .and include('err1').and include('err2')
    end

    it 'mirrors the wrapped command exit code in separate_streams mode, same as the default mode' do
      result = described_class.new(['bash', '-c', 'exit 3'], separate_streams: true).run

      expect(result).to be_success
      expect(result.exit_code).to eq(3)
    end

    it 'does not add clean_stdout/clean_stderr to the result data when separate_streams is not ' \
       'set (regression guard: the default result data shape must stay byte-for-byte unchanged)' do
      result = described_class.new('echo hi').run

      expect(result.data).not_to have_key(:clean_stdout)
      expect(result.data).not_to have_key(:clean_stderr)
    end

    it 'kills the timed-out child in separate_streams mode too, instead of leaving it orphaned' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'pid')
        runner = described_class.new(
          ['ruby', '-e', "File.write(#{pid_file.inspect}, Process.pid); sleep 10"],
          separate_streams: true, timeout_seconds: 3
        )

        result = runner.run
        child_pid = File.read(pid_file).strip.to_i
        sleep 0.2

        expect(result.data[:exit_code]).to eq(124)
        expect(result.data[:clean_stdout]).to eq('')
        expect(result.data[:clean_stderr]).to eq('')
        expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
      end
    end

    it 'forwards SIGINT to the child in separate_streams mode too' do
      runner = described_class.new('sleep 10', separate_streams: true, timeout_seconds: 30)

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

    # read_separate_streams has its own abort rescue (IO.select over two readers rather than
    # read_pty_stream's single wait_readable), so the escalation ladder is covered here too.
    it 'ends a separate_streams run on a second signal, reaping the child and keeping both ' \
       'streams' do
      Dir.mktmpdir do |dir|
        pid_path = File.join(dir, 'child.pid')
        ready = false
        watch_ready = ->(chunk) { ready ||= chunk.include?('ready') }
        runner = described_class.new(['ruby', '-e', <<~RUBY], separate_streams: true, timeout_seconds: 8,
          Signal.trap('INT') { $stdout.puts 'out INT'; $stderr.puts 'err INT' }
          $stdout.sync = true
          $stderr.sync = true
          File.write(#{pid_path.inspect}, Process.pid)
          puts 'ready'
          sleep 30
        RUBY
                                     &watch_ready)

        signaller = Thread.new do
          Timeout.timeout(10) { sleep 0.02 until ready }
          Process.kill('INT', Process.pid)
          sleep 0.4
          Process.kill('INT', Process.pid)
        end

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = runner.run
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        signaller.join(5)
        child_pid = File.read(pid_path).strip.to_i

        expect(result).to be_success
        expect(result.data[:exit_code]).to eq(130)
        expect(result.data[:clean_stdout].scan('out INT').size).to eq(2)
        expect(result.data[:clean_stderr].scan('err INT').size).to eq(2)
        expect(elapsed).to be < 6
        expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
      end
    end

    it 'rejects combining separate_streams: true with script: (the interactive DSL only ' \
       'supports the merged single-stream view)' do
      script = Rune::Script.new { wait_for(/x/) }
      result = described_class.new('echo hi', separate_streams: true, script: script).run

      expect(result).to be_failure
      expect(result.error).to include('separate_streams').and include('script')
    end

    it 'still handles missing/non-executable commands with the conventional 127/126 exit codes ' \
       'in separate_streams mode' do
      result = described_class.new('non_existent_command_xyz_12345', separate_streams: true).run

      expect(result).to be_success
      expect(result.data[:exit_code]).to eq(127)
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

    # A child that traps INT/TERM and keeps going is not hypothetical — it is
    # every agent CLI that turns the first Ctrl-C into "interrupt this turn".
    # Before the escalation ladder, rune latched after the first forward, so
    # signals two onward were swallowed: rune neither passed them on nor died,
    # and the only bound left was --timeout (with `rune watch`, nothing at all).
    it 'gives up and returns a well-formed interrupted result when a second signal arrives, ' \
       'instead of running on to --timeout' do
      Dir.mktmpdir do |dir|
        pid_path = File.join(dir, 'child.pid')
        ready = false
        # timeout_seconds is deliberately still generous: if the second signal
        # were swallowed again this example would report 124 at ~8s, not 130.
        # The handler *prints*, which is not incidental: a pty child that is
        # SIGKILLed while bytes it wrote sit unread in the pty buffer wedges
        # permanently in the macOS kernel exit path and can never be reaped
        # again. A silent child hides that entirely — this example passed
        # against an implementation that hung the real CLI for minutes.
        watch_ready = ->(chunk) { ready ||= chunk.include?('ready') }
        runner = described_class.new(['ruby', '-e', <<~RUBY], timeout_seconds: 8, &watch_ready)
          Signal.trap('INT') { $stdout.puts 'child: caught INT' }
          Signal.trap('TERM') { $stdout.puts 'child: caught TERM' }
          $stdout.sync = true
          File.write(#{pid_path.inspect}, Process.pid)
          puts 'ready'
          sleep 30
        RUBY

        signaller = Thread.new do
          Timeout.timeout(10) { sleep 0.02 until ready }
          Process.kill('INT', Process.pid)
          sleep 0.4
          Process.kill('INT', Process.pid)
        end

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = runner.run
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        signaller.join(5)
        child_pid = File.read(pid_path).strip.to_i

        expect(result).to be_success
        expect(result.data[:exit_code]).to eq(130)
        expect(result.data[:clean_output]).to include('ready').and include('Interrupted by SIGINT')
        # Both interrupts reached the child, and the second one's output was
        # still drained into the result rather than lost with the teardown.
        expect(result.data[:clean_output].scan('child: caught INT').size).to eq(2)
        expect(result.data[:duration_ms]).to be_a(Numeric)
        expect(elapsed).to be < 6
        # Reaped, not orphaned: the whole reason rune traps at all is so the
        # child is dealt with rather than left behind.
        expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
      end
    end

    # The case the fix must not lose: a lone signal is still the child's to
    # handle, and rune keeps waiting on it. Escalation is about a *repeated*
    # signal, not about rune bailing out the instant one arrives and orphaning
    # the child — which is exactly why the traps were installed in the first
    # place.
    it 'still gives a signal-handling child its first signal and keeps waiting on it, rather than ' \
       'aborting on the very first one' do
      Dir.mktmpdir do |dir|
        marker_path = File.join(dir, 'trapped')
        ready = false
        watch_ready = ->(chunk) { ready ||= chunk.include?('ready') }
        runner = described_class.new(['ruby', '-e', <<~RUBY], timeout_seconds: 10, &watch_ready)
          Signal.trap('INT') { File.write(#{marker_path.inspect}, 'trapped') }
          $stdout.sync = true
          puts 'ready'
          sleep 0.05 until File.exist?(#{marker_path.inspect})
          puts 'still here'
          exit 7
        RUBY

        signaller = Thread.new do
          Timeout.timeout(10) { sleep 0.02 until ready }
          Process.kill('INT', Process.pid)
        end

        result = runner.run
        signaller.join(5)

        expect(result).to be_success
        expect(File.exist?(marker_path)).to be true
        expect(result.data[:clean_output]).to include('still here')
        expect(result.data[:exit_code]).to eq(7)
      end
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
