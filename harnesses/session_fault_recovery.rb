# frozen_string_literal: true

# Session failure and recovery, against a fresh checkout.
#
# Proves the cases the suite did not already pin down together:
# a clean exit and a nonzero exit agree across read, list, and meta; a send
# that is in flight when the child exits comes back with child_exited and the
# child's own marker; a read can see the child still running and then exited;
# a late answer is not the echo of the caller's nonce; a catastrophic regex
# is abandoned without a wall-clock assertion; restarting a name after the
# supervisor is killed does not keep the old transcript or signal the orphan;
# stop does not signal an unrelated process-group leader.
#
# Every run sets RUNE_HOME to a private directory. The controller's fixture
# home is used as the parent when it is set and is not ~/.rune. Subprocesses
# inherit that directory. Only pids this process spawned, or that its own
# session meta recorded, are signalled, and only when both the recorded start
# time and the current start time are present and equal. A missing or
# mismatched identity is a refusal, not a reason to signal. A pid this process
# has already reaped with Process.wait is a no-op. A nil start time is not
# that confirmation. Signals use a positive pid, never a process group.
# There is no attach and no scan of another home.
#
# A nonce is never the marker a case waits for. The echo of the nonce can
# satisfy a sloppy pattern; these cases do not give it that chance.
#
# The 4096-byte check is a sanity bound on these short fixtures. It does not
# request --max-output and it does not assert truncation.
#
# The read-exit case is two sequential reads: one while the child is held,
# and one after release. It is not an overlapped in-flight read. The send-exit
# case is an in-flight send.
#
# Broken controls stage a disposable checkout under the fixture home: a copy
# of lib/ with one literal fault, and a copy of bin/rune beside it. The
# supervisor is not this process. spawn_supervisor re-invokes bin/rune from
# the directory of the loaded session_command.rb, and that script loads
# ../lib/rune. The staged layout is what makes the fault the code that runs.
# The candidate lib/ and bin/rune are not edited. Before a fault observation,
# the controller's loaded files and the bin the supervisor will execute are
# checked to be that same copy. A failed check exits before the assertion, so
# it is a setup failure rather than a killed regression. Assertions with no
# such fault are live-only; a JSON stand-in or a rewritten child is not used.
#
# The old_child copy calls signal_owned_fixture. That is the same positive-pid
# and start-time guard. A missing, blank, mismatched, or untracked pid raises
# and is not signalled.
#
# The default ~/.rune path is canonicalized only when that directory already
# exists. A missing default home stays the expanded path. Nothing creates it.
#
# Cleanup records identity refusals and pids that remain after a guarded
# signal. Either one keeps the fixture directory and fails the scenario.
# Disappearance is not a reap. RUNE_HOME and module state are restored in an
# ensure that still runs when reaping raises.
#
#   ruby -Ilib harnesses/session_fault_recovery.rb
#   ruby -Ilib harnesses/session_fault_recovery.rb broken

require 'English'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'securerandom'
require 'tmpdir'

module SessionFaultLoadPath
  module_function

  def install
    fault = ENV.fetch('RUNE_FAULT_LIB', nil)
    if fault.nil? || fault.strip.empty?
      lib = File.expand_path('../lib', __dir__)
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      return
    end

    expanded = File.realpath(fault)
    home = ENV.fetch('RUNE_HOME', nil)
    raise 'RUNE_FAULT_LIB requires RUNE_HOME' if home.nil? || home.strip.empty?

    root = File.realpath(home)
    raise 'RUNE_FAULT_LIB refuses ~/.rune' if refuses_default?(root, Dir.home)
    raise 'RUNE_FAULT_LIB must stay inside RUNE_HOME' unless inside?(expanded, root)

    real_lib = File.realpath(File.expand_path('../lib', __dir__))
    raise 'RUNE_FAULT_LIB must not be the candidate lib' if expanded == real_lib || inside?(expanded, real_lib)

    $LOAD_PATH.unshift(expanded)
  end

  def inside?(path, root)
    path == root || path.start_with?(root + File::SEPARATOR)
  end

  # realpath only when the directory is already there. A missing default home
  # is the expanded path, and this does not create it.
  def default_home_for(home_directory)
    expanded = File.expand_path('.rune', home_directory.to_s)
    File.exist?(expanded) ? File.realpath(expanded) : expanded
  end

  def refuses_default?(root, home_directory)
    candidate = File.exist?(root) ? File.realpath(root) : File.expand_path(root.to_s)
    candidate == default_home_for(home_directory)
  end
end

SessionFaultLoadPath.install
require 'rune'

module SessionFaultRecovery
  # Short-fixture sanity ceiling. Not --max-output, and not a truncation claim.
  BOUND = 4_096
  # Existence checks after a guarded signal. Not a clock assertion.
  DISAPPEAR_CHECKS = 5
  DISAPPEAR_PAUSE = 0.02
  private_constant :BOUND, :DISAPPEAR_CHECKS, :DISAPPEAR_PAUSE

  EXIT_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    STDOUT.sync = true
    puts ARGV.fetch(0)
    exit ARGV.fetch(1).to_i
  RUBY

  READ_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    STDOUT.sync = true
    release = ARGV.fetch(0)
    puts ARGV.fetch(1)
    until File.exist?(release)
      sleep 0.05
    end
    exit ARGV.fetch(2).to_i
  RUBY

  SEND_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    STDOUT.sync = true
    STDIN.gets
    puts ARGV.fetch(0)
    exit ARGV.fetch(1).to_i
  RUBY

  LATE_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    STDOUT.sync = true
    release = ARGV.fetch(0)
    proof_path = ARGV.fetch(1)
    proof = ARGV.fetch(2)
    marker = ARGV.fetch(3)
    STDIN.gets
    until File.exist?(release)
      sleep 0.05
    end
    File.write(proof_path, proof)
    puts marker
  RUBY

  REGEX_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    STDOUT.sync = true
    STDIN.gets
    puts(('a' * 60) + 'b')
    sleep 30
  RUBY

  SURVIVOR_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    Signal.trap('HUP', 'IGNORE')
    Signal.trap('TERM', 'IGNORE')
    STDOUT.sync = true
    puts ARGV.fetch(0)
    sleep 300
  RUBY

  SLEEPER_CHILD = <<~'RUBY'
    # frozen_string_literal: true
    sleep 300
  RUBY

  def regex_supported? = Regexp.method_defined?(:timeout)

  def observe_exit(code) = isolate { observe_exit_in(want: code) }

  def observe_read_exit = isolate { observe_read_exit_in }

  def observe_send_exit = isolate { observe_send_exit_in }

  def observe_late = isolate { observe_late_in }

  def observe_regex = isolate { observe_regex_in }

  def observe_reconnect = isolate { observe_reconnect_in }

  def observe_bystander = isolate { observe_bystander_in }

  # The recorder stands in for Process.kill. A refusal must leave it empty,
  # and the owned child must still have the start time recorded before the probe.
  def probe_missing_recorded_identity
    identity_probe do |pid, recorded, calls|
      @kill_impl = kill_recorder(calls)
      @tracked[pid] = nil
      refused = refuse_signal(pid)
      @tracked[pid] = recorded
      { kill_calls: calls, refused: refused, survived: same_start?(pid, recorded), noop: false }
    end
  end

  def probe_missing_current_identity
    identity_probe do |pid, recorded, calls|
      @kill_impl = kill_recorder(calls)
      @start_reader = ->(_ignored) { nil }
      refused = refuse_signal(pid)
      { kill_calls: calls, refused: refused, survived: same_start?(pid, recorded), noop: false }
    end
  end

  def probe_mismatched_identity
    identity_probe do |pid, recorded, calls|
      @kill_impl = kill_recorder(calls)
      @start_reader = ->(_ignored) { "#{recorded} stale" }
      refused = refuse_signal(pid)
      { kill_calls: calls, refused: refused, survived: same_start?(pid, recorded), noop: false }
    end
  end

  # The confirming reap is a real kill of this owned child, and only after its
  # start time matched. The second call is the no-op under test.
  def probe_confirmed_dead
    identity_probe do |pid, _recorded, calls|
      signal_fixture(pid)
      raise 'dead probe did not reap its own child' unless reaped?(pid)

      @kill_impl = kill_recorder(calls)
      signal_fixture(pid)
      { kill_calls: calls, refused: false, survived: false, noop: calls.empty? }
    end
  end

  # The copied old_child fault calls this. It uses the same guard as cleanup.
  def signal_owned_fixture(pid)
    signal_fixture(pid)
  end

  def cleanup_report
    @cleanup_report
  end

  def disappear_checks
    DISAPPEAR_CHECKS
  end

  # Injected existence and wait. The recorder stands in for Process.kill.
  # A pid that stays present must fail the scenario and keep the directory.
  # The old cleanup ignored still_present, deleted the directory, and returned.
  def probe_unresolved_still_present
    cleanup_double(:still_present)
  end

  # A missing recorded identity must not signal. The live pid is preserved.
  def probe_cleanup_refusal
    cleanup_double(:refusal)
  end

  # An error while checking presence must restore the environment and must
  # not reach Process.kill.
  def probe_cleanup_error
    cleanup_double(:error)
  end

  # Loaded controller files and the supervisor bin must be the staged copy.
  # Raising here is a setup failure, not a killed regression.
  def assert_fault_load!(scenario)
    relative = fault_target(scenario)
    fault = File.realpath(ENV.fetch('RUNE_FAULT_LIB'))
    raise 'RUNE_FAULT_LIB is the candidate lib' if fault == candidate_lib

    loaded = loaded_fault_sources
    loaded.each do |name, path|
      real = File.realpath(path)
      expected = File.realpath(File.join(fault, name))
      raise "#{name} loaded #{real}, not the staged copy" unless real == expected

      original = File.realpath(File.join(candidate_lib, name))
      raise "#{name} is the candidate file" if real == original
    end

    command = File.realpath(loaded.fetch('rune/commands/session_command.rb'))
    bin = File.realpath(File.expand_path('../../../bin/rune', File.dirname(command)))
    raise 'supervisor bin is the candidate bin' if bin == candidate_bin

    bin_text = File.read(bin)
    unless bin_text.include?("require_relative '../lib/rune'")
      raise 'staged bin does not load ../lib/rune'
    end

    supervisor_lib = File.realpath(File.expand_path('../lib', File.dirname(bin)))
    raise 'supervisor lib is not the controller fault lib' unless supervisor_lib == fault

    mutated = File.realpath(File.join(fault, relative))
    raise 'controller did not load the mutated file' unless File.realpath(loaded.fetch(relative)) == mutated
    raise 'staged file matches the candidate bytes' if File.read(mutated) == File.read(File.join(candidate_lib, relative))
  end

  def exit_problems(obs)
    problems = []
    problems << 'start' unless obs[:start_ok]
    problems << 'exit_code' unless exits_agree?(obs)
    problems << 'agreement' unless states_are?(obs, 'exited')
    problems << 'marker' unless marker_once?(obs[:output], obs[:marker])
    problems << 'echo' if contains_marker?(obs[:sent], obs[:marker])
    problems << 'bounds' unless bounded?(obs)
    problems << 'cleanup' unless dead?(obs)
    problems << 'stable' unless obs[:cursor] == obs[:cursor_again] && obs[:output] == obs[:output_again]
    problems
  end

  def read_problems(obs)
    problems = []
    problems << 'running' unless obs[:running_state] == 'running' && obs[:running_exit].nil?
    problems << 'running_marker' unless marker_once?(obs[:running_output], obs[:marker])
    problems << 'exit_code' unless obs[:exit_code] == obs[:want_exit]
    problems << 'agreement' unless states_are?(obs, 'exited')
    problems << 'marker' unless marker_once?(obs[:output], obs[:marker])
    problems << 'echo' if contains_marker?(obs[:sent], obs[:marker])
    problems << 'bounds' unless bounded?(obs)
    problems << 'stable' unless obs[:cursor] == obs[:cursor_again] && obs[:output] == obs[:output_again]
    problems << 'cleanup' unless dead?(obs)
    problems
  end

  def send_problems(obs)
    problems = []
    problems << 'status' unless obs[:status] == 'ok'
    problems << 'child_exited' unless obs[:child_exited] == true
    problems << 'timed_out' if obs[:timed_out] == true
    problems << 'marker' unless marker_once?(obs[:output], obs[:marker])
    problems << 'echo' if contains_marker?(obs[:sent], obs[:marker])
    problems << 'bounds' unless bounded?(obs)
    problems << 'exit_code' unless exits_agree?(obs)
    problems << 'agreement' unless states_are?(obs, 'exited')
    problems << 'cleanup' unless dead?(obs)
    problems
  end

  def late_problems(obs)
    problems = []
    problems << 'matched' unless obs[:matched] == true
    problems << 'late' unless obs[:echo_before_release] == true
    problems << 'marker' unless marker_once?(obs[:output], obs[:marker])
    problems << 'echo' if contains_marker?(obs[:sent], obs[:marker])
    problems << 'proof' unless obs[:proof_seen] == true
    problems << 'bounds' unless bounded?(obs)
    problems
  end

  def regex_problems(obs)
    problems = []
    problems << 'status' unless obs[:status] == 'ok'
    problems << 'regex_timed_out' unless obs[:regex_timed_out] == true
    problems << 'settled' unless obs[:settled] == false
    problems << 'echo' if obs[:matched] == true
    problems << 'pattern' if obs[:pattern_matches_sent] == true
    problems << 'pumped' unless obs[:output].to_s.include?('a' * 60)
    problems << 'running' unless obs[:state] == 'running' && obs[:exit_code].nil?
    problems << 'child_alive' unless obs[:child_alive] == true
    problems << 'supervisor_alive' unless obs[:supervisor_alive] == true
    problems << 'bounds' unless bounded?(obs)
    problems
  end

  def reconnect_problems(obs)
    problems = []
    problems << 'dead' unless obs[:dead_state] == 'dead' && obs[:read_dead_state] == 'dead'
    problems << 'old_child' unless obs[:old_child_alive_after_death] == true &&
                                    obs[:old_child_alive_after_restart] == true
    problems << 'old_identity' unless obs[:old_start_same] == true
    problems << 'reset' if contains_marker?(obs[:new_output], obs[:old_marker])
    problems << 'new_marker' unless marker_once?(obs[:new_output], obs[:new_marker])
    problems << 'echo' if contains_marker?(obs[:sent], obs[:new_marker])
    problems << 'exit_code' unless obs[:exit_code] == 0 && obs[:list_exit] == 0 && obs[:meta_exit] == 0
    problems << 'new_supervisor' unless obs[:new_supervisor_pid] && obs[:new_supervisor_pid] != obs[:old_supervisor_pid]
    problems << 'bounds' unless bounded?(obs.merge(output: obs[:new_output], bytes: obs[:bytes]))
    problems << 'cleanup' unless obs[:new_child_alive] == false && obs[:new_supervisor_alive] == false
    problems
  end

  def bystander_problems(obs)
    problems = []
    problems << 'stop' unless obs[:stop_ok] == true && obs[:state] == 'stopped'
    problems << 'cleanup' unless obs[:child_alive] == false && obs[:supervisor_alive] == false
    problems << 'bystander' unless obs[:bystander_alive] == true && obs[:bystander_same_start] == true
    problems << 'distinct' unless obs[:bystander_pid] && obs[:bystander_pid] != obs[:child_pid] &&
                                   obs[:bystander_pid] != obs[:supervisor_pid]
    problems << 'leader' unless obs[:bystander_leads_group] == true
    problems
  end

  # Each fault is one literal edit in a disposable checkout. The subprocess
  # runs the same observation and the same predicate as the live example.
  # The candidate tree is not modified. Tags with no such fault are absent.
  def broken_controls
    isolate do
      controls = [
        rune_fault('exit_code', 'exit_code', EXIT_CODE_FAULT, 'exit_code'),
        rune_fault('marker', 'marker', MARKER_FAULT, 'marker'),
        rune_fault('child_exited', 'child_exited', CHILD_EXITED_FAULT, 'child_exited'),
        rune_fault('running', 'running', RUNNING_FAULT, 'running'),
        rune_fault('reset', 'reset', RESET_FAULT, 'reset'),
        rune_fault('old_child', 'old_child', OLD_CHILD_FAULT, 'old_child')
      ]
      controls << rune_fault('regex_timed_out', 'regex_timed_out', REGEX_FAULT, 'regex_timed_out') if regex_supported?
      controls
    end
  end

  def main(argv)
    if argv == ['broken']
      bad = broken_controls.reject { |control| control[:setup_ok] && control[:problems].include?(control[:tag]) }
      broken_controls_report(bad)
      return bad.empty?
    end

    failures = live_report
    failures.empty?
  end

  private

  # One substitution each, applied only to the disposable copy.
  EXIT_CODE_FAULT = ['rune/session/supervisor.rb',
                     "meta = { state: 'exited', exit_code: exit_code, exited_at: Time.now.to_f }",
                     "meta = { state: 'exited', exit_code: 0, exited_at: Time.now.to_f }",
                     false].freeze
  MARKER_FAULT = ['rune/commands/session_command.rb',
                  "{ action: 'read', name: options[:name], output: bounded,",
                  "{ action: 'read', name: options[:name], output: 'withheld',",
                  false].freeze
  CHILD_EXITED_FAULT = ['rune/session/pending_send.rb',
                        '{ settled: true, child_exited: true }',
                        '{ settled: true }',
                        true].freeze
  RUNNING_FAULT = ['rune/commands/session_command.rb',
                   '{ state: resolved_state(meta), exit_code: meta[:exit_code] }.compact',
                   '{ state: resolved_state(meta), exit_code: meta.fetch(:exit_code, 5) }.compact',
                   false].freeze
  RESET_FAULT = ['rune/commands/session_command.rb',
                 "        store.reset_transcript(name)\n",
                 '',
                 false].freeze
  OLD_CHILD_FAULT = ['rune/commands/session_command.rb',
                     "      def launch(name, command)\n        store.create(name)\n",
                     "      def launch(name, command)\n" \
                     "        orphan = (store.read_meta(name) || {})[:child_pid].to_i\n" \
                     "        SessionFaultRecovery.signal_owned_fixture(orphan) if orphan.positive?\n" \
                     "        store.create(name)\n",
                     false].freeze
  REGEX_FAULT = ['rune/session/pending_send.rb',
                 'return { settled: false, regex_timed_out: true } if matched.nil?',
                 'return { settled: true, matched: false } if matched.nil?',
                 false].freeze

  FAULT_RUNNER = <<~'RUBY'
    # frozen_string_literal: true
    require 'json'
    require ARGV.fetch(0)
    scenario = ARGV.fetch(1)
    SessionFaultRecovery.assert_fault_load!(scenario)
    problems = case scenario
               when 'exit_code', 'marker'
                 SessionFaultRecovery.exit_problems(SessionFaultRecovery.observe_exit(3))
               when 'child_exited'
                 SessionFaultRecovery.send_problems(SessionFaultRecovery.observe_send_exit)
               when 'running'
                 SessionFaultRecovery.read_problems(SessionFaultRecovery.observe_read_exit)
               when 'regex_timed_out'
                 SessionFaultRecovery.regex_problems(SessionFaultRecovery.observe_regex)
               when 'reset', 'old_child'
                 SessionFaultRecovery.reconnect_problems(SessionFaultRecovery.observe_reconnect)
               else
                 raise "unknown fault scenario #{scenario}"
               end
    $stdout.write(JSON.generate(problems: problems))
  RUBY

  def live_report
    checks = [
      ['exit 0', -> { [exit_problems(observe_exit(0)), observe_note] }],
      ['exit 3', -> { [exit_problems(observe_exit(3)), observe_note] }],
      ['read exit', -> { [read_problems(observe_read_exit), observe_note] }],
      ['send exit', -> { [send_problems(observe_send_exit), observe_note] }],
      ['late output', -> { [late_problems(observe_late), observe_note] }],
      ['reconnect', -> { [reconnect_problems(observe_reconnect), observe_note] }],
      ['bystander', -> { [bystander_problems(observe_bystander), observe_note] }]
    ]
    checks << ['regex timeout', -> { [regex_problems(observe_regex), observe_note] }] if regex_supported?
    failures = []
    checks.each do |name, runner|
      problems, note = runner.call
      if problems.empty?
        puts "#{name} ok"
      else
        failures << name
        puts "#{name} FAIL #{problems.join(',')} #{note}"
      end
    end
    failures
  end

  def observe_note = @last_obs&.inspect

  def remember(obs)
    @last_obs = obs
    obs
  end

  def broken_controls_report(bad)
    if bad.empty?
      puts 'broken controls failed closed'
    else
      bad.each { |control| puts "#{control[:name]} HELD #{control[:problems].inspect} #{control[:error]}" }
    end
  end

  def observe_exit_in(want:, source: EXIT_CHILD, name: "exit#{want}")
    marker = token('mark')
    script = write_fixture("#{name}.rb", source)
    start = start_session(name, [RbConfig.ruby, script, marker, want.to_s])
    exited = poll_read(name, 'the child exit to be recorded') { |data| data[:state] == 'exited' }
    again = read_data(name)
    remember(surfaces(name, exited).merge(
      start_ok: start.success?, want_exit: want, marker: marker, sent: '',
      output_again: again[:output].to_s, cursor_again: again[:cursor]
    ))
  end

  # Two reads, one after the other. Release is written only after the first
  # read has already returned. This does not overlap a read with the exit.
  def observe_read_exit_in
    marker = token('mark')
    release = fixture_path('release-read')
    script = write_fixture('read_exit.rb', READ_CHILD)
    name = 'readexit'
    start_session(name, [RbConfig.ruby, script, release, marker, '5'])
    running = poll_read(name, 'the marker while the child is still running') do |data|
      data[:state] == 'running' && marker_once?(data[:output], marker)
    end
    File.write(release, '1')
    exited = poll_read(name, 'the read to observe the exit') { |data| data[:state] == 'exited' }
    again = read_data(name)
    remember(surfaces(name, exited).merge(
      want_exit: 5, marker: marker, sent: '',
      running_state: running[:state], running_exit: running[:exit_code],
      running_output: running[:output].to_s,
      output_again: again[:output].to_s, cursor_again: again[:cursor]
    ))
  end

  def observe_send_exit_in(source: SEND_CHILD, name: 'sendexit', timeout_ms: 8_000)
    marker = token('mark')
    sent = token('ask')
    script = write_fixture("#{name}.rb", source)
    start_session(name, [RbConfig.ruby, script, marker, '9'])
    reply = session('send', "--name=#{name}", '--settle-ms=8000', "--timeout-ms=#{timeout_ms}", '--', sent)
    data = reply.data || {}
    exited = poll_read(name, 'the exit after the in-flight send') { |row| row[:state] == 'exited' }
    remember(surfaces(name, exited).merge(
      status: reply.success? ? 'ok' : 'error', error: reply.error,
      child_exited: data[:child_exited], timed_out: data[:timed_out], settled: data[:settled],
      output: data[:output].to_s, bytes: data[:output].to_s.bytesize,
      marker: marker, sent: sent, want_exit: 9
    ))
  end

  def observe_late_in(source: LATE_CHILD, name: 'lateout')
    marker = token('late')
    sent = token('ask')
    proof = token('proof')
    release = fixture_path("#{name}-release")
    proof_path = fixture_path("#{name}-proof")
    script = write_fixture("#{name}.rb", source)
    start_session(name, [RbConfig.ruby, script, release, proof_path, proof, marker])
    holder = {}
    thread = Thread.new do
      holder[:reply] = session(
        'send', "--name=#{name}", '--settle-ms=30000', '--timeout-ms=8000',
        "--wait-for-regex=#{Regexp.escape(marker)}", '--', sent
      )
    rescue StandardError => error
      holder[:error] = error
    end
    echo_before = false
    begin
      wait_until('the echo of the nonce, before the late marker') do
        text = read_data(name)[:output].to_s
        text.include?(sent) && !text.include?(marker)
      end
      echo_before = true
      File.write(release, '1')
      thread.join(30)
    ensure
      File.write(release, '1') unless File.exist?(release)
      if thread.alive?
        supervisor = (store.read_meta(name) || {})[:supervisor_pid]
        signal_fixture(supervisor) if supervisor
        thread.join(10)
      end
    end
    raise holder[:error] if holder[:error]
    reply = holder[:reply] || Rune::Result.failure('send thread produced no reply')
    data = reply.data || {}
    output = data[:output].to_s
    remember(
      status: reply.success? ? 'ok' : 'error', error: reply.error,
      matched: data[:matched], output: output, bytes: output.bytesize,
      marker: marker, sent: sent, echo_before_release: echo_before,
      proof_seen: File.exist?(proof_path) && File.read(proof_path) == proof
    )
  end

  def observe_regex_in(source: REGEX_CHILD, name: 'retime')
    pattern = '(a+)+\1$'
    sent = 'go'
    script = write_fixture("#{name}.rb", source)
    start_session(name, [RbConfig.ruby, script])
    reply = session(
      'send', "--name=#{name}", '--settle-ms=30000', '--timeout-ms=8000',
      "--wait-for-regex=#{pattern}", '--', sent
    )
    data = reply.data || {}
    meta = store.read_meta(name) || {}
    output = data[:output].to_s
    remember(
      status: reply.success? ? 'ok' : 'error', error: reply.error,
      regex_timed_out: data[:regex_timed_out], settled: data[:settled], matched: data[:matched],
      output: output, bytes: output.bytesize, state: data[:state], exit_code: data[:exit_code],
      pattern_matches_sent: Regexp.new(pattern).match?(sent),
      child_alive: alive?(meta[:child_pid]), supervisor_alive: alive?(meta[:supervisor_pid])
    )
  end

  def observe_reconnect_in
    old_marker = token('old')
    new_marker = token('new')
    script = write_fixture('survivor.rb', SURVIVOR_CHILD)
    name = 'reconn'
    start_session(name, [RbConfig.ruby, script, old_marker])
    poll_read(name, 'the survivor marker') { |data| data[:output].to_s.include?(old_marker) }
    meta = store.read_meta(name) || {}
    old_child = meta[:child_pid]
    old_supervisor = meta[:supervisor_pid]
    old_started = @tracked[Integer(old_child)]
    signal_fixture(old_supervisor)
    dead = poll_read(name, 'the supervisor disappearance') { |data| data[:state] == 'dead' }
    listed_dead = listed(name)
    after_death = Rune::Session::Store.process_start_time(old_child)
    fresh = write_fixture('fresh.rb', EXIT_CHILD)
    start_session(name, [RbConfig.ruby, fresh, new_marker, '0'])
    exited = poll_read(name, 'the restarted child to exit') do |data|
      data[:state] == 'exited' && data[:output].to_s.include?(new_marker)
    end
    after_restart = Rune::Session::Store.process_start_time(old_child)
    new_meta = store.read_meta(name) || {}
    restarted = listed(name)
    output = exited[:output].to_s
    same_identity = old_started && old_started == after_death && old_started == after_restart
    remember(
      dead_state: listed_dead[:state], read_dead_state: dead[:state],
      old_child_alive_after_death: alive?(old_child) && after_death == old_started,
      old_start_same: same_identity, old_child_alive_after_restart: alive?(old_child),
      old_marker: old_marker, new_marker: new_marker, new_output: output, sent: '',
      exit_code: exited[:exit_code], list_exit: restarted[:exit_code], meta_exit: new_meta[:exit_code],
      bytes: output.bytesize,
      old_supervisor_pid: old_supervisor, new_supervisor_pid: new_meta[:supervisor_pid],
      new_child_alive: alive?(new_meta[:child_pid]), new_supervisor_alive: alive?(new_meta[:supervisor_pid])
    )
  end

  def observe_bystander_in
    pid = Process.spawn(
      RbConfig.ruby, '-e', 'Signal.trap("HUP","IGNORE"); Signal.trap("TERM","IGNORE"); sleep 300',
      pgroup: true, in: File::NULL, out: File::NULL, err: File::NULL
    )
    track(pid)
    started = @tracked[pid]
    leads = Process.getpgid(pid) == pid
    name = 'bystand'
    script = write_fixture("#{name}.rb", SLEEPER_CHILD)
    started_session = start_session(name, [RbConfig.ruby, script])
    meta = store.read_meta(name) || {}
    stopped = session('stop', "--name=#{name}")
    listed_row = listed(name)
    remember(
      stop_ok: stopped.success?, state: listed_row[:state],
      child_pid: meta[:child_pid], supervisor_pid: meta[:supervisor_pid],
      child_alive: alive?(meta[:child_pid]), supervisor_alive: alive?(meta[:supervisor_pid]),
      bystander_pid: pid, bystander_alive: alive?(pid),
      bystander_same_start: started && started == Rune::Session::Store.process_start_time(pid),
      bystander_leads_group: leads, start_ok: started_session.success?
    )
  end

  def surfaces(name, read)
    row = listed(name)
    meta = store.read_meta(name) || {}
    output = read[:output].to_s
    {
      output: output, bytes: output.bytesize, cursor: read[:cursor],
      read_state: read[:state], exit_code: read[:exit_code],
      list_state: row[:state], list_exit: row[:exit_code],
      meta_state: meta[:state], meta_exit: meta[:exit_code],
      child_alive: alive?(meta[:child_pid]), supervisor_alive: alive?(meta[:supervisor_pid])
    }
  end

  def exits_agree?(obs)
    obs[:exit_code] == obs[:want_exit] && obs[:list_exit] == obs[:want_exit] && obs[:meta_exit] == obs[:want_exit]
  end

  def states_are?(obs, state)
    [obs[:read_state], obs[:list_state], obs[:meta_state]].all? { |item| item == state }
  end

  def dead?(obs) = obs[:child_alive] == false && obs[:supervisor_alive] == false

  def bounded?(obs)
    size = obs[:bytes].to_i
    size.positive? && size <= BOUND && size == obs[:output].to_s.bytesize
  end

  def marker_once?(text, marker)
    !marker.to_s.empty? && text.to_s.scan(marker.to_s).length == 1
  end

  def contains_marker?(text, marker)
    !marker.to_s.empty? && text.to_s.include?(marker.to_s)
  end

  def isolate
    return yield if @inside

    previous = ENV.fetch('RUNE_HOME', nil)
    parent = controller_parent(previous)
    dir = parent ? Dir.mktmpdir('f', parent) : Dir.mktmpdir('rune-fault')
    remember_evidence_root(parent, dir)
    @inside = true
    @home = dir
    @project = Rune::Session::Store.project_slug
    @tracked = {}
    @reaped = {}
    @kill_impl = nil
    @start_reader = nil
    @exists_impl = nil
    @wait_impl = nil
    @real_kills = []
    @cleanup_report = nil
    ENV['RUNE_HOME'] = dir
    failure = nil
    result = nil
    begin
      result = yield
    rescue StandardError => caught
      failure = caught
    ensure
      restore_isolate(dir, previous)
    end
    raise cleanup_failure(failure) if cleanup_blocked?

    raise failure if failure

    result
  end

  def controller_parent(raw)
    return nil if raw.nil? || raw.strip.empty?

    expanded = File.expand_path(raw)
    return nil if SessionFaultLoadPath.refuses_default?(expanded, Dir.home)

    FileUtils.mkdir_p(expanded)
    expanded
  end

  def remember_evidence_root(parent, dir)
    current = ENV.fetch('RUNE_FAULT_EVIDENCE', nil)
    return if current && !current.strip.empty?

    ENV['RUNE_FAULT_EVIDENCE'] = parent || File.dirname(dir)
  end

  def restore_isolate(dir, previous)
    report = { reaped: [], absent: [], refused_alive: [], still_present: [], error: nil, preserved: nil }
    begin
      report = reap_tracked
    rescue StandardError => caught
      report[:error] = "#{caught.class}: #{caught.message}"
    ensure
      @tracked = {}
      @reaped = {}
      @home = nil
      @inside = false
      @kill_impl = nil
      @start_reader = nil
      @exists_impl = nil
      @wait_impl = nil
      if previous.nil?
        ENV.delete('RUNE_HOME')
      else
        ENV['RUNE_HOME'] = previous
      end
      @cleanup_report = report
      finish_fixture(dir, report)
    end
  end

  def finish_fixture(dir, report)
    if unresolved?(report) || report[:error]
      report[:preserved] = archive_ambiguous(dir, report)
    else
      FileUtils.remove_entry(dir)
    end
  rescue StandardError => caught
    report[:preserve_error] = "#{caught.class}: #{caught.message}"
    report[:preserved] ||= dir
    (@preserved_fixtures ||= []) << dir
  end

  def archive_ambiguous(dir, report)
    root = ENV.fetch('RUNE_FAULT_EVIDENCE', File.dirname(dir))
    park = File.join(root, 'preserved-fixtures')
    FileUtils.mkdir_p(park)
    destination = File.join(park, "#{File.basename(dir)}-#{SecureRandom.hex(3)}")
    FileUtils.mv(dir, destination)
    report[:preserved] = destination
    File.write(File.join(destination, 'cleanup-refusal.json'), JSON.generate(report))
    (@preserved_fixtures ||= []) << destination
    destination
  end

  def unresolved?(report)
    Array(report[:refused_alive]).any? || Array(report[:still_present]).any?
  end

  def cleanup_blocked?
    report = @cleanup_report || {}
    report[:error] || report[:preserve_error] || unresolved?(report)
  end

  def cleanup_failure(failure)
    report = @cleanup_report || {}
    alive = Array(report[:refused_alive]) + Array(report[:still_present])
    detail = +'cleanup failed closed'
    detail << ": #{report[:error]}" if report[:error]
    detail << ": #{report[:preserve_error]}" if report[:preserve_error]
    detail << " left alive #{alive.inspect}" if alive.any?
    detail << " preserved #{report[:preserved]}"
    detail << " after #{failure.class}: #{failure.message}" if failure
    detail
  end

  def session(*args)
    command = Rune::Commands::SessionCommand.new
    command.instance_variable_set(:@project_override, @project)
    command.instance_variable_set(:@store, Rune::Session::Store.new(home: @home, project: @project))
    command.call(args.map(&:to_s), {})
  end

  def store = Rune::Session::Store.new(home: @home, project: @project)

  def start_session(name, argv)
    result = session('start', "--name=#{name}", '--', *argv)
    raise "start #{name} failed: #{result.error}" if result.failure?

    remember_session(name)
    result
  end

  def remember_session(name)
    meta = store.read_meta(name) || {}
    track(meta[:child_pid])
    track(meta[:supervisor_pid])
  end

  def read_data(name)
    result = session('read', "--name=#{name}")
    raise "read #{name} failed: #{result.error}" if result.failure?

    result.data
  end

  def listed(name)
    result = session('list')
    raise "list failed: #{result.error}" if result.failure?

    result.data[:sessions].find { |entry| entry[:name] == name } || {}
  end

  def poll_read(name, reason)
    found = nil
    wait_until(reason) do
      data = read_data(name)
      found = data if yield(data)
    end
    found
  end

  def wait_until(reason, timeout: 15)
    deadline = monotonic + timeout
    until yield
      raise "timed out waiting for #{reason}" if monotonic > deadline

      sleep 0.02
    end
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def token(prefix) = "#{prefix}-#{SecureRandom.hex(6)}"

  def fixture_path(name) = File.join(@home, name)

  def write_fixture(name, body)
    path = fixture_path(name)
    File.write(path, body)
    path
  end

  def track(pid)
    return if pid.nil?

    pid = Integer(pid)
    return unless pid.positive?
    return if @tracked.key?(pid)

    started = nil
    5.times do
      started = Rune::Session::Store.process_start_time(pid)
      break if started

      sleep 0.02
    end
    @tracked[pid] = started
  end

  def alive?(pid)
    return false if pid.nil?

    Rune::Session::Store.alive?(pid)
  end

  # A refusal is not signalled again. Absence is not a reap. A pid that is
  # still present after the bounded existence checks stays unresolved.
  def reap_tracked
    report = { reaped: [], absent: [], refused_alive: [], still_present: [], error: nil, preserved: nil }
    (@tracked || {}).each_key do |pid|
      signal_fixture(pid)
      if reaped?(pid)
        report[:reaped] << pid
      elsif await_disappearance(pid)
        report[:absent] << { pid: pid, reason: 'gone without Process.wait' }
      else
        report[:still_present] << { pid: pid, reason: 'still present after bounded disappearance checks' }
      end
    rescue ArgumentError => refusal
      classify_refusal(report, pid, refusal)
    end
    report
  end

  def classify_refusal(report, pid, refusal)
    if fixture_exists?(pid)
      report[:refused_alive] << { pid: pid, reason: refusal.message }
    else
      report[:absent] << { pid: pid, reason: refusal.message }
    end
  end

  # No signal and no negative pid. Injected checks skip the pause.
  def await_disappearance(pid)
    DISAPPEAR_CHECKS.times do
      return true unless fixture_exists?(pid)

      sleep DISAPPEAR_PAUSE unless @exists_impl
    end
    false
  end

  # Existence only. This does not signal, and it never uses a negative pid.
  def fixture_exists?(pid)
    number = Integer(pid)
    return false unless number.positive?

    return @exists_impl.call(number) if @exists_impl

    Process.getpgid(number)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def signal_fixture(pid)
    pid = Integer(pid)
    raise ArgumentError, "refusing to signal non-positive pid #{pid}" unless pid.positive?

    decision = refusal(pid)
    return if decision == :dead
    raise ArgumentError, decision if decision

    deliver_kill(pid)
    wait_child(pid)
  rescue Errno::ESRCH
    nil
  end

  # :dead is only a pid this process reaped with Process.wait. A nil start
  # time is not death and is not permission to signal.
  def refusal(pid)
    return "refusing to signal non-fixture pid #{pid}" unless @tracked.key?(pid)
    return :dead if reaped?(pid)

    recorded = @tracked[pid]
    if recorded.nil? || recorded.to_s.strip.empty?
      return "refusing to signal pid #{pid} with no recorded identity"
    end

    current = current_start(pid)
    if current.nil? || current.to_s.strip.empty?
      return "refusing to signal pid #{pid} with no current identity"
    end
    return "refusing to signal reused pid #{pid}" unless recorded == current

    nil
  end

  def current_start(pid)
    return @start_reader.call(pid) if @start_reader

    Rune::Session::Store.process_start_time(pid)
  end

  def deliver_kill(pid)
    if @kill_impl
      @kill_impl.call('KILL', pid)
      return
    end

    (@real_kills ||= []) << pid
    Process.kill('KILL', pid)
  end

  def wait_child(pid)
    if @wait_impl
      mark_reaped(pid) if @wait_impl.call(Integer(pid))
      return
    end
    return if @kill_impl

    Process.wait(Integer(pid))
    mark_reaped(pid)
  rescue Errno::ECHILD
    nil
  end

  def reaped?(pid)
    @reaped ||= {}
    @reaped[pid] == true
  end

  def mark_reaped(pid)
    @reaped ||= {}
    @reaped[pid] = true
  end

  def identity_probe
    isolate do
      pid = spawn_owned_sleeper
      recorded = @tracked[pid]
      raise 'owned sleeper has no start time' if recorded.nil? || recorded.to_s.strip.empty?

      begin
        yield(pid, recorded, [])
      ensure
        @start_reader = nil
        @kill_impl = nil
        unless reaped?(pid)
          @tracked[pid] = recorded
          signal_fixture(pid)
        end
      end
    end
  end

  def spawn_owned_sleeper
    pid = Process.spawn(RbConfig.ruby, '-e', 'sleep 300', in: File::NULL, out: File::NULL, err: File::NULL)
    track(pid)
    pid
  end

  def kill_recorder(calls)
    lambda do |_signal, target|
      calls << Integer(target)
    end
  end

  def refuse_signal(pid)
    signal_fixture(pid)
    false
  rescue ArgumentError
    true
  end

  def same_start?(pid, recorded)
    Rune::Session::Store.process_start_time(pid) == recorded
  end

  # Synthetic positive pids only. track is not used, because it asks ps.
  # Existence, wait, and kill are the injected doubles for the whole reap.
  def cleanup_double(mode)
    pid = 2_147_483_000 + { still_present: 1, refusal: 2, error: 3 }.fetch(mode)
    calls = []
    exists_calls = []
    wait_calls = []
    before = ENV.fetch('RUNE_HOME', nil)
    raised = nil
    begin
      isolate do
        @kill_impl = kill_recorder(calls)
        @exists_impl = lambda do |target|
          exists_calls << Integer(target)
          raise 'injected existence failure' if mode == :error

          true
        end
        @wait_impl = lambda do |target|
          wait_calls << Integer(target)
          false
        end
        @tracked[pid] = mode == :still_present ? 'owned-start' : nil
        @start_reader = ->(_ignored) { 'owned-start' } if mode == :still_present
        :scenario_ok
      end
    rescue StandardError => error
      raised = "#{error.class}: #{error.message}"
    end
    report = @cleanup_report || {}
    {
      pid: pid, raised: raised, kill_calls: calls, real_kills: Array(@real_kills),
      exists_calls: exists_calls, wait_calls: wait_calls,
      reaped: Array(report[:reaped]), absent: Array(report[:absent]),
      refused_alive: Array(report[:refused_alive]), still_present: Array(report[:still_present]),
      preserved: report[:preserved], error: report[:error],
      home_before: before, home_after: ENV.fetch('RUNE_HOME', nil),
      home_restored: ENV.fetch('RUNE_HOME', nil) == before,
      inside: @inside == true, tracked_cleared: @tracked.nil? || @tracked.empty?
    }
  end

  def rune_fault(name, tag, fault, scenario)
    relative, from, to, replace_all = fault
    copy = stage_fault_lib(relative, from, to, replace_all: replace_all)
    script = write_fixture("fault-#{name}.rb", FAULT_RUNNER)
    env = ENV.to_h.merge('RUNE_FAULT_LIB' => copy, 'RUNE_HOME' => @home)
    stdout, stderr, status = Open3.capture3(
      env, RbConfig.ruby, script, File.expand_path(__FILE__), scenario,
      chdir: File.expand_path('..', __dir__)
    )
    unless status.success?
      raise "copied rune #{name} exited #{status.exitstatus}: #{stderr}"
    end

    parsed = JSON.parse(stdout, symbolize_names: true)
    { name: name, tag: tag, problems: parsed.fetch(:problems), setup_ok: true }
  rescue StandardError => error
    { name: name, tag: tag, problems: [], setup_ok: false, error: "#{error.message} #{stderr}" }
  end

  # Checkout shape, not a bare lib directory. session_command.rb computes
  # executable_path as ../../../bin/rune from its own directory, and bin/rune
  # loads ../lib/rune. A bare copy would send the supervisor at a missing
  # path, or at the candidate, and the fault would never run.
  def stage_fault_lib(relative, from, to, replace_all:)
    source = candidate_lib
    real_path = File.realpath(File.join(source, relative))
    before = File.read(real_path)
    bin_path = candidate_bin
    bin_before = File.read(bin_path)
    stage = File.join(@home, "fault-#{SecureRandom.hex(4)}")
    lib_copy = File.join(stage, 'lib')
    FileUtils.mkdir_p(File.join(stage, 'bin'))
    FileUtils.cp_r(source, lib_copy)
    FileUtils.cp(bin_path, File.join(stage, 'bin/rune'))
    mutate_copy(lib_copy, relative, from, to, replace_all: replace_all)
    raise "fault edit touched the candidate lib #{relative}" if File.read(real_path) != before
    raise 'fault edit touched the candidate bin' if File.read(bin_path) != bin_before

    staged_bin = File.realpath(File.join(stage, 'bin/rune'))
    resolved = File.expand_path('../../../bin/rune', File.join(lib_copy, 'rune/commands'))
    raise 'staged supervisor bin escaped the checkout' if File.realpath(resolved) != staged_bin
    raise 'staged lib escaped the fixture home' unless SessionFaultLoadPath.inside?(File.realpath(lib_copy), File.realpath(@home))

    lib_copy
  end

  def candidate_lib
    File.realpath(File.expand_path('../lib', __dir__))
  end

  def candidate_bin
    File.realpath(File.expand_path('../bin/rune', __dir__))
  end

  def fault_target(scenario)
    targets = {
      'exit_code' => 'rune/session/supervisor.rb',
      'marker' => 'rune/commands/session_command.rb',
      'child_exited' => 'rune/session/pending_send.rb',
      'running' => 'rune/commands/session_command.rb',
      'regex_timed_out' => 'rune/session/pending_send.rb',
      'reset' => 'rune/commands/session_command.rb',
      'old_child' => 'rune/commands/session_command.rb'
    }
    targets.fetch(scenario) { raise "unknown fault scenario #{scenario}" }
  end

  def loaded_fault_sources
    {
      'rune/commands/session_command.rb' =>
        Rune::Commands::SessionCommand.instance_method(:launch).source_location.fetch(0),
      'rune/session/supervisor.rb' =>
        Rune::Session::Supervisor.instance_method(:finish).source_location.fetch(0),
      'rune/session/pending_send.rb' =>
        Rune::Session::PendingSend.instance_method(:answered).source_location.fetch(0)
    }
  end

  def mutate_copy(root, relative, from, to, replace_all:)
    root_real = File.realpath(root)
    path = File.realpath(File.join(root, relative))
    raise "fault edit escaped the copy #{relative}" unless SessionFaultLoadPath.inside?(path, root_real)

    text = File.read(path)
    count = literal_count(text, from)
    raise "fault pattern missing in #{relative}" if count.zero?
    raise "fault pattern repeated in #{relative}" if !replace_all && count > 1
    raise "fault pattern count #{count} in #{relative}" if replace_all && count != 2

    updated, replaced = literal_replace(text, from, to, replace_all: replace_all)
    raise "fault did not change #{relative}" if updated == text || replaced != (replace_all ? 2 : 1)

    File.write(path, updated)
  end

  def literal_count(text, needle)
    count = 0
    start = 0
    while (index = text.index(needle, start))
      count += 1
      start = index + needle.length
    end
    count
  end

  # Index replacement, not String#sub. The needles contain brackets, dots,
  # parentheses, and a question mark. The edit must be those exact bytes.
  def literal_replace(text, needle, replacement, replace_all:)
    pieces = []
    cursor = 0
    replaced = 0
    while (found = text.index(needle, cursor))
      pieces << text[cursor...found] << replacement
      cursor = found + needle.length
      replaced += 1
      break unless replace_all
    end
    pieces << text[cursor..]
    [pieces.join, replaced]
  end

  extend self
end

if $PROGRAM_NAME == __FILE__
  exit(SessionFaultRecovery.main(ARGV) ? 0 : 1)
end
