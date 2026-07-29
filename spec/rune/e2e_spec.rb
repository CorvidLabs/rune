# frozen_string_literal: true

require 'spec_helper'
require 'io/wait'
require 'shellwords'
require 'tmpdir'

RSpec.describe 'rune binary E2E' do
  let(:bin_path) { File.expand_path('../../bin/rune', __dir__) }

  it 'runs version command in piped mode (defaults to JSON)' do
    output = `ruby #{bin_path} version`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:status]).to eq('ok')
    expect(parsed[:data][:name]).to eq('rune')
  end

  it 'runs version command in JSON mode' do
    output = `ruby #{bin_path} version --json`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:status]).to eq('ok')
    expect(parsed[:data][:name]).to eq('rune')
  end

  it 'runs version command in NDJSON mode' do
    output = `ruby #{bin_path} version --ndjson`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:event]).to eq('result')
    expect(parsed[:status]).to eq('ok')
  end

  it 'executes git status via rune run in JSON mode' do
    skip 'pty stdlib unavailable on this platform' unless Rune::PTYRunner.pty_available?

    output = `ruby #{bin_path} run --json git status`
    parsed = JSON.parse(output, symbolize_names: true)
    expect(parsed[:status]).to eq('ok')
    expect(parsed[:data][:command]).to eq('git status')
    expect(parsed[:data][:clean_output]).to match(/On branch|HEAD detached|nothing to commit/)
  end

  # In agent mode stdout carries the structured envelope and nothing else, for
  # every command. Asserted against the real executable, over the *entire*
  # captured stdout, with a real JSON parser — not a substring match.
  #
  # That distinction is the whole point of this group. `rune watch --json` used
  # to write the wrapped child's live output to stdout (PTYWatcher's `output:`
  # defaults to `$stdout`, and WatchCommand never passed it) and only then let
  # the Renderer append the envelope, producing
  # `"PURITY_PROBE\r\n{\"status\":\"ok\",...}"`. Every substring-style
  # assertion in the suite passed against that; only parsing whole stdout
  # catches it.
  describe 'stdout purity in agent mode' do
    # argv (after the command name) that makes each command do real work
    let(:invocations) do
      {
        'help' => [],
        'version' => [],
        'run' => ['--', 'echo', 'PURITY_PROBE'],
        'watch' => ['--', 'echo', 'PURITY_PROBE']
      }
    end

    # `watch` refuses to start unless stdin is a real terminal, so it has to be
    # driven through a pty. stdout is redirected to a file inside that pty
    # session, which is exactly the agent-mode shape under test: a real
    # terminal on stdin, a non-terminal on stdout.
    let(:needs_tty_stdin) { %w[watch] }

    def capture(argv, tty_stdin:)
      Dir.mktmpdir do |dir|
        out = File.join(dir, 'stdout')
        err = File.join(dir, 'stderr')
        command = "#{Shellwords.escape(RbConfig.ruby)} #{Shellwords.escape(bin_path)} " \
                  "#{argv.shelljoin} > #{Shellwords.escape(out)} 2> #{Shellwords.escape(err)}"
        tty_stdin ? run_under_pty(command) : system(command, in: File::NULL)
        { stdout: File.read(out), stderr: File.read(err) }
      end
    end

    def run_under_pty(command)
      PTY.spawn({ 'TERM' => 'dumb' }, 'sh', '-c', command) do |reader, _writer, pid|
        begin
          loop do
            break unless reader.wait_readable(30)

            reader.readpartial(4096)
          end
        rescue Errno::EIO, EOFError, PTY::ChildExited
          nil
        end
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
          nil
        end
      end
    end

    # `Rune::CLI.commands` is process-global and other spec files register their
    # own fixture commands into it (`spec-only-boom`, and similar), which stay
    # there for the rest of the run. Scope to the shipped `Rune::Commands::*`
    # classes so this stays a real completeness gate — adding a fourth genuine
    # command fails here until it is given an invocation above — rather than a
    # test that breaks whenever an unrelated spec file defines a fixture.
    it 'covers every shipped command, so a new command cannot silently skip this gate' do
      # `klass.to_s`, not `klass.name`: the `Command` DSL defines a class-level
      # `name(cmd_name)` that shadows `Module#name`, so the usual accessor
      # raises ArgumentError on a Command subclass.
      shipped = Rune::CLI.commands.select { |_, klass| klass.to_s.start_with?('Rune::Commands::') }.keys
      expect(invocations.keys).to match_array(shipped + ['help'])
    end

    # `--json` and `--ndjson` are explicit; the third case is a bare invocation
    # with stdout redirected, which must reach the same place through the
    # Renderer's non-TTY detection.
    [['--json'], ['--ndjson'], []].each do |flags|
      label = flags.empty? ? 'piped stdout (no flag)' : flags.join(' ')

      # `JSON.parse` over the whole string is the entire assertion, and it is
      # sufficient: it rejects leading garbage, trailing garbage, and
      # concatenated documents alike. `JSON.parse("PURITY_PROBE\r\n{...}")`
      # raises, which is exactly the bug this guards against. Deliberately not
      # asserted here: that the probe string is absent from stdout — `rune run`
      # legitimately returns the child's output inside `clean_output`, and
      # `watch` echoes the argv back in `command`.
      it "emits only a parseable structured document on stdout for every command in #{label}" do
        skip 'pty stdlib unavailable on this platform' unless Rune::PTYRunner.pty_available?

        invocations.each do |command, args|
          streams = capture([command, *flags, *args], tty_stdin: needs_tty_stdin.include?(command))

          expect { JSON.parse(streams[:stdout]) }.not_to(
            raise_error,
            "rune #{command} #{label}: stdout is not one JSON document: #{streams[:stdout].inspect}"
          )
        end
      end
    end

    # The complement of the purity rule: routed away from stdout, but not
    # thrown away. A human is still driving the session even when a wrapping
    # process is capturing stdout, so the live view has to remain visible.
    it 'still shows the watched child\'s live output, on stderr, when stdout carries the envelope' do
      skip 'pty stdlib unavailable on this platform' unless Rune::PTYRunner.pty_available?

      streams = capture(['watch', '--json', '--', 'echo', 'PURITY_PROBE'], tty_stdin: true)

      expect(streams[:stderr]).to include('PURITY_PROBE')
      expect(JSON.parse(streams[:stdout])).to include('status' => 'ok')
    end
  end
end
