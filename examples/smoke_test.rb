#!/usr/bin/env ruby
# frozen_string_literal: true

# A runnable, assertion-based tour of rune's behavior — including every bug
# fixed during 0.2.0 launch prep. Complements spec/ (which is what CI runs
# via `fledge run test`): this is the "run it by hand and see it work" version
# of the same guarantees, useful for a manual sanity check on a machine/
# platform you don't have RSpec set up on, or after touching PTYRunner/
# SignalHandler/Script internals.
#
# Run it with:
#   ruby examples/smoke_test.rb
# or:
#   fledge run smoke-test
#
# Exits non-zero if anything fails, so it's safe to wire into CI too.

require_relative '../lib/rune'
require 'json'
require 'open3'
require 'pty'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

# Top-level ivars on `main`, shared across the top-level `def`s below (a
# top-level `def` is a private method on Object, invoked with self == main).
@pass = []
@fail = []

def check(description)
  yield
  @pass << description
  puts "  \e[32m✓\e[0m #{description}"
rescue StandardError => e
  @fail << [description, e.message]
  puts "  \e[31m✗\e[0m #{description}"
  puts "      #{e.class}: #{e.message}"
end

def section(title)
  puts "\n\e[1m#{title}\e[0m"
  yield
end

def assert(condition, message)
  raise message unless condition
end

RUNE_BIN = File.expand_path('../bin/rune', __dir__)

# Builds an identical two-step script via whichever factory method is given
# (Rune::Script.method(:new) or .method(:define)), so both can be compared.
def two_step_script(build_method)
  build_method.call do
    wait_for(/x/)
    send_keys("y\n")
  end
end

# Runs `ruby bin/rune <args>`, returns [stdout, exit_status]. Shells out to a
# real subprocess (rather than calling Rune::CLI in-process) so this exercises
# the exact same process-exit-code path a real caller would see.
def run_cli(*args)
  out, status = Open3.capture2(RbConfig.ruby, RUNE_BIN, *args)
  [out, status.exitstatus]
end

def run_cli_tty(*args)
  output = +''
  status = nil
  PTY.spawn(RbConfig.ruby, RUNE_BIN, *args) do |reader, _writer, pid|
    loop { output << reader.readpartial(4096) }
  rescue Errno::EIO, EOFError, PTY::ChildExited
    _, status = Process.wait2(pid)
  end
  [output, status&.exitstatus]
end

section('rune version — output modes') do
  check('human mode prints a version line') do
    out, status = run_cli_tty('version')
    assert(out.include?(Rune::VERSION), "expected version #{Rune::VERSION} in #{out.inspect}")
    assert(out.include?('Ruby') && !out.include?('"status"'), "expected human TTY output, got #{out.inspect}")
    assert(status&.zero?, "expected exit 0, got #{status.inspect}")
  end

  check('--json emits the {"status":"ok",...} envelope') do
    out, = run_cli('version', '--json')
    parsed = JSON.parse(out)
    assert(parsed['status'] == 'ok', out)
    assert(parsed['data']['version'] == Rune::VERSION, out)
  end

  check('--ndjson wraps the same payload in an event envelope') do
    out, = run_cli('version', '--ndjson')
    parsed = JSON.parse(out)
    assert(parsed['event'] == 'result', out)
  end
end

section('rune run — basics') do
  check('captures stdout and a zero exit code on success') do
    out, status = run_cli('run', '--json', '--', 'echo', 'hello smoke test')
    data = JSON.parse(out)['data']
    assert(data['exit_code'].zero?, data.inspect)
    assert(data['clean_output'].include?('hello smoke test'), data.inspect)
    assert(status.zero?, "rune process itself should exit 0, got #{status}")
  end

  check('exit-code composability: rune process mirrors the wrapped command exit code') do
    _, status = run_cli('run', '--json', '--', 'ruby', '-e', 'exit 42')
    assert(status == 42, "expected rune to exit 42 (the wrapped command's code), got #{status}")
  end

  check('missing command reports exit 127 without crashing') do
    out, status = run_cli('run', '--json', '--', 'this_definitely_does_not_exist_xyz')
    data = JSON.parse(out)['data']
    assert(data['exit_code'] == 127, data.inspect)
    assert(status == 127, "rune process should mirror exit 127, got #{status}")
  end

  check('wrapped commands emitting non-UTF-8 bytes do not crash rune (found via real dogfooding)') do
    out, = run_cli('run', '--json', '--', 'printf', '\xff\xfe\x00binary garbage\n')
    parsed = JSON.parse(out)
    assert(parsed['status'] == 'ok', out)
    assert(parsed['data']['clean_output'].include?('binary garbage'), out)
  end
end

section('rune run --timeout') do
  check('valid --timeout overrides the default and is honored') do
    out, = run_cli('run', '--json', '--timeout=1', '--', 'sleep', '3')
    data = JSON.parse(out)['data']
    assert(data['exit_code'] == 124, data.inspect)
    assert(data['duration_ms'] < 2000, "expected ~1s timeout, took #{data['duration_ms']}ms")
  end

  %w[0 -5 abc 3.5].each do |bad|
    check("--timeout=#{bad} is rejected instead of leaking into the command") do
      out, status = run_cli('run', '--json', "--timeout=#{bad}", '--', 'echo', 'hi')
      parsed = JSON.parse(out)
      assert(parsed['status'] == 'error', out)
      assert(parsed['error'].include?('Invalid --timeout value'), out)
      assert(status == 1, status.to_s)
    end
  end

  check('a --timeout-looking flag AFTER -- is passed through untouched') do
    out, = run_cli('run', '--json', '--', 'printf', '%s\n', '--timeout=5')
    data = JSON.parse(out)['data']
    assert(data['clean_output'].include?('--timeout=5'), data.inspect)
  end
end

section('rune run — argv passthrough') do
  check('a literal -- inside the wrapped command survives (found via real external dogfooding: ' \
        '`cargo clippy --tests -- -D warnings` had its inner -- silently eaten)') do
    out, = run_cli('run', '--json', '--', 'printf', '%s\n', '--', 'foo')
    data = JSON.parse(out)['data']
    assert(data['command'].include?('-- foo'), data.inspect)
    assert(data['clean_output'].include?("--\nfoo"), data.inspect)
  end

  check('--json and --ndjson after rune\'s -- separator reach the wrapped command') do
    out, = run_cli(
      'run', '--json', '--', 'ruby', '-e', 'puts ARGV.inspect', '--', '--json', '--ndjson'
    )
    data = JSON.parse(out)['data']
    assert(data['clean_output'].include?('["--json", "--ndjson"]'), data.inspect)
  end
end

section('Rune::Parsers::TableParser') do
  check(':auto detects space-delimited tables') do
    rows = Rune::Parsers::TableParser.parse("NAME STATUS\nrune active\n")
    assert(rows == [{ name: 'rune', status: 'active' }], rows.inspect)
  end

  check(':pipe forces markdown-table parsing even without a separator row') do
    rows = Rune::Parsers::TableParser.parse("Name | Status\nrune | active", format: :pipe)
    assert(rows == [{ name: 'rune', status: 'active' }], rows.inspect)
  end

  check(':space forces whitespace parsing, treating a literal | as cell content') do
    rows = Rune::Parsers::TableParser.parse("NAME  NOTE\nrune  a|b", format: :space)
    assert(rows == [{ name: 'rune', note: 'a|b' }], rows.inspect)
  end

  check('an unknown format raises ArgumentError') do
    Rune::Parsers::TableParser.parse("a b\n1 2\n", format: :csv)
    raise 'expected ArgumentError, none raised'
  rescue ArgumentError
    nil
  end
end

section('Rune::Parsers::KeyValueParser') do
  check('coerces int/float/bool and leaves strings (incl. colons) alone') do
    parsed = Rune::Parsers::KeyValueParser.parse(
      "count: 5\nratio: 1.5\nactive: true\nurl: http://example.com:8080\n"
    )
    assert(parsed == { count: 5, ratio: 1.5, active: true, url: 'http://example.com:8080' }, parsed.inspect)
  end
end

section('Rune::Script — the .new-silently-empty fix') do
  check('Script.new { ... } builds steps identically to Script.define { ... }') do
    new_script = two_step_script(Rune::Script.method(:new))
    define_script = two_step_script(Rune::Script.method(:define))
    assert(new_script.steps.map(&:type) == define_script.steps.map(&:type), new_script.steps.inspect)
    got = new_script.steps.size
    assert(got == 2, "Script.new silently discarded its block again! (#{got} steps)")
  end

  check('Script.new { ... } actually drives a real interactive PTY prompt') do
    ruby_code = <<~RUBY
      puts "Name?"
      name = $stdin.gets&.strip
      puts "Hi \#{name}"
    RUBY
    script = Rune::Script.new do
      wait_for(/Name\?/)
      send_keys "Claude\n"
    end
    result = Rune::PTYRunner.new(['ruby', '-e', ruby_code], script: script, timeout_seconds: 5).run
    assert(result.success? && result.data[:clean_output].include?('Hi Claude'), result.data.inspect)
  end
end

section('Signal forwarding') do
  # These checks pin rune's contract rather than the child's disposition. The
  # previous version of this section sent ONE signal and asserted the run ended,
  # which
  # passed only because `sleep` happens to die on SIGINT. Run where SIGINT is
  # inherited as ignored — exactly what a task runner does, and how this was
  # caught — the child inherits SIG_IGN, the forwarded signal does nothing,
  # rune correctly keeps waiting, and the check failed at 10.01s. It was
  # asserting the child's disposition, not rune's contract.
  # The child announces receipt, so forwarding is observable rather than
  # inferred. It has to be Ruby rather than a shell `trap`: POSIX lets a shell
  # decline to trap a signal it inherited as ignored, and under a task runner
  # INT *is* inherited as ignored, so a shell child would silently prove
  # nothing. `Signal.trap` installs over SIG_IGN either way.
  check('one SIGINT is forwarded to the child and rune keeps waiting') do
    child = "#{RbConfig.ruby} -e 'Signal.trap(\"INT\") { puts \"GOT_INT\"; $stdout.flush }; sleep 4'"
    runner = Rune::PTYRunner.new(child, timeout_seconds: 30)
    Thread.new do
      sleep 1.0
      Process.kill('INT', Process.pid)
    end
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = runner.run
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    assert(result.data[:clean_output].include?('GOT_INT'),
           "the signal never reached the child: #{result.data[:clean_output].inspect}")
    assert(elapsed > 2, "one signal must not end the run, returned after #{elapsed.round(2)}s")
    assert(result.data[:exit_code].zero?, "expected the child's own exit, got #{result.data.inspect}")
  end
end

section('Signal escalation') do
  check('a second SIGINT stops rune promptly at 130, even though the child ignores it') do
    runner = Rune::PTYRunner.new('trap "" INT; sleep 30', timeout_seconds: 60)
    Thread.new do
      sleep 0.3
      Process.kill('INT', Process.pid)
      sleep 0.3
      Process.kill('INT', Process.pid)
    end
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = runner.run
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    assert(elapsed < 10, "expected early termination, took #{elapsed.round(2)}s")
    assert(result.data[:exit_code] == 130, result.data.inspect)
  end
end

section('Rune::Parsers::PromptDetector') do
  check('detects real shell prompts and interactive questions') do
    assert(Rune::Parsers::PromptDetector.detect?('user@host:~$ '), 'shell prompt')
    assert(Rune::Parsers::PromptDetector.detect?('Continue? (y/n) '), 'y/n question')
    assert(Rune::Parsers::PromptDetector.detect?('Password: '), 'password prompt')
  end

  check('does not misdetect digit-percent progress output as a prompt') do
    assert(!Rune::Parsers::PromptDetector.detect?('Building... 45%'), 'false positive on "Building... 45%"')
    assert(!Rune::Parsers::PromptDetector.detect?('Downloading 100%'), 'false positive on "Downloading 100%"')
  end
end

section('PTY-unavailable handling (simulated — this platform has a working pty)') do
  check('PTYRunner#run fails cleanly if the pty stdlib never loaded') do
    allow_pty_available = Rune::PTYRunner.method(:pty_available?)
    Rune::PTYRunner.define_singleton_method(:pty_available?) { false }
    result = Rune::PTYRunner.new('echo hi').run
    assert(result.failure? && result.error.include?('PTY unavailable'), result.error)
  ensure
    Rune::PTYRunner.define_singleton_method(:pty_available?, allow_pty_available)
  end

  check('PTYRunner#run fails cleanly if the OS refuses pty allocation at runtime') do
    require 'pty'
    original = PTY.method(:spawn)
    PTY.define_singleton_method(:spawn) { |*| raise Errno::ENXIO, 'no ptys available' }
    result = Rune::PTYRunner.new('echo hi').run
    assert(result.failure? && result.error.include?('PTY allocation failed at runtime'), result.error)
  ensure
    PTY.define_singleton_method(:spawn, original)
  end
end

section('Rune::PTYWatcher — live bidirectional passthrough (rune watch)') do
  check('fails clearly instead of attempting anything when stdin is not a tty') do
    result = Rune::PTYWatcher.new('echo hi', input: StringIO.new).watch
    assert(result.failure? && result.error.include?('requires a real terminal'), result.error)
  end

  check('forwards live input to the child and streams its output back, round-trip') do
    require 'delegate'
    fake_terminal = Class.new(SimpleDelegator) { def tty? = true }
    human_in_r, human_in_w = IO.pipe
    log_r, log_w = IO.pipe
    output = +''
    writer = Object.new
    writer.define_singleton_method(:write) { |s| output << s }
    writer.define_singleton_method(:flush) { nil }

    ruby_code = "puts 'Name?'; name = $stdin.gets&.strip; puts \"Hi \#{name}!\""
    watcher = Rune::PTYWatcher.new(['ruby', '-e', ruby_code], log: log_w,
                                                              input: fake_terminal.new(human_in_r), output: writer)
    thread = Thread.new { watcher.watch }
    sleep 0.3
    human_in_w.write("Claude\n")
    result = thread.value
    log_w.close

    assert(result.success? && output.include?('Hi Claude!'), output)
    events = log_r.read.each_line.map { |line| JSON.parse(line) }
    assert(events.first['event'] == 'start' && events.last['event'] == 'exit', events.inspect)
  end
end

section('Rune::Commands::WatchCommand — default log destination') do
  check('fails fast on non-tty stdin without creating a stray log file (real usage showed ' \
        'logging to stderr by default made the live session unreadable, so it now defaults ' \
        'to an announced temp file instead)') do
    before = Dir.glob(File.join(Dir.tmpdir, 'rune-watch-*.ndjson'))
    result = Rune::Commands::WatchCommand.new.call(%w[-- echo hi], {})
    after = Dir.glob(File.join(Dir.tmpdir, 'rune-watch-*.ndjson'))

    assert(result.failure? && result.error.include?('requires a real terminal'), result.error)
    assert(after == before, "expected no new rune-watch-*.ndjson temp files, got #{after - before}")
  end
end

puts "\n#{@pass.size} passed, #{@fail.size} failed"
unless @fail.empty?
  puts "\nFailures:"
  @fail.each { |desc, msg| puts "  - #{desc}\n    #{msg}" }
end
exit(@fail.empty? ? 0 : 1)
