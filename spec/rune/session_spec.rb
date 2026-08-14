# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'socket'
require 'fileutils'

# These are the first specs in this suite that drive real *detached*
# out-of-process children, so cleanup is not optional bookkeeping: a leaked
# supervisor outlives the run and keeps a pty open. Every example runs against
# its own temp RUNE_HOME and is force-reaped afterwards regardless of outcome.
RSpec.describe Rune::Commands::SessionCommand do
  # A child shaped like a real agent CLI: the tty echoes the input immediately,
  # then the process thinks for a beat before answering. The delay is the whole
  # point — it is what distinguishes "settled on the echo" (wrong) from
  # "settled on the response" (right).
  def thinking_child(delay: 1.0)
    script = <<~CHILD
      STDOUT.sync = true
      while (line = STDIN.gets)
        sleep #{delay}
        puts 'REPLY:' + line.strip
      end
    CHILD
    ['ruby', '-e', script]
  end

  around do |example|
    Dir.mktmpdir('rune-sess') do |dir|
      @home = dir
      previous = ENV.fetch('RUNE_HOME', nil)
      ENV['RUNE_HOME'] = dir
      begin
        example.run
      ensure
        reap_everything
        ENV['RUNE_HOME'] = previous
      end
    end
  end

  def store = Rune::Session::Store.new(home: @home)

  def session(*args)
    described_class.new.call(args.map(&:to_s), {})
  end

  def start_session(name, command)
    result = session('start', "--name=#{name}", '--', *command)
    raise "start failed: #{result.error}" if result.failure?

    result
  end

  # Condition-polled, never a fixed sleep. This repo has been bitten repeatedly
  # by timing-tuned tests (CHG-0027 and the SIGINT/demo_tui race before it);
  # poll for the observable condition instead of guessing a margin.
  def wait_until(timeout: 15, reason: 'condition')
    deadline = monotonic + timeout
    until yield
      raise "timed out waiting for #{reason}" if monotonic > deadline

      sleep 0.02
    end
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def reap_everything
    store.names.each do |name|
      meta = store.read_meta(name) || {}
      [meta[:child_pid], meta[:supervisor_pid]].compact.each do |pid|
        Process.kill('KILL', Integer(pid))
      rescue Errno::ESRCH, Errno::EPERM, TypeError, ArgumentError
        next
      end
    end
  end

  describe 'persistence across invocations' do
    it 'keeps the child alive after the starting call returns, and answers a later send' do
      start_session('s1', ['bash', '--norc', '-i'])

      # The supervisor is a separate process, so this second call reaches the
      # same child the first call started — the core claim of the feature.
      result = session('send', '--name=s1', '--settle-ms=300', '--timeout-ms=15000', '--', 'echo alive-and-well')

      expect(result).to be_success
      expect(result.data[:output]).to include('alive-and-well')
    end

    it 'preserves child state between separate sends' do
      start_session('s2', ['bash', '--norc', '-i'])
      session('send', '--name=s2', '--settle-ms=300', '--timeout-ms=15000', '--', 'MEMORY=persisted')

      result = session('send', '--name=s2', '--settle-ms=300', '--timeout-ms=15000', '--', 'echo "value=$MEMORY"')

      expect(result.data[:output]).to include('value=persisted')
    end
  end

  describe 'send-and-settle' do
    # Regression for the defect that made the first working build subtly
    # useless: a pty echoes input straight back, so the echo alone satisfied
    # "output arrived" and the send settled before the child had answered,
    # handing the caller its own words back.
    it 'does not settle on the pty echo of the input while the child is still thinking' do
      start_session('s3', thinking_child(delay: 1.0))

      result = session('send', '--name=s3', '--settle-ms=250', '--timeout-ms=15000', '--', 'ping')

      expect(result.data[:settled]).to be true
      expect(result.data[:output]).to include('REPLY:ping')
    end

    it 'returns only output produced after the send' do
      start_session('s4', thinking_child(delay: 0.1))
      session('send', '--name=s4', '--settle-ms=250', '--timeout-ms=15000', '--', 'first')

      result = session('send', '--name=s4', '--settle-ms=250', '--timeout-ms=15000', '--', 'second')

      expect(result.data[:output]).to include('REPLY:second')
      expect(result.data[:output]).not_to include('REPLY:first')
    end

    it 'returns as soon as --wait-for-regex matches, without waiting out the settle window' do
      start_session('s5', thinking_child(delay: 0.1))

      started = monotonic
      result = session('send', '--name=s5', '--settle-ms=10000', '--timeout-ms=15000',
                       '--wait-for-regex=REPLY:', '--', 'quick')

      expect(result.data[:matched]).to be true
      expect(monotonic - started).to be < 5
    end

    # Found by an independent review (grok). --wait-for-regex is documented as
    # the deterministic escape hatch, but it matched the raw slice — including
    # the pty's echo of the input — so waiting for a marker you just asked the
    # agent to print returned your own words instantly. That is the normal way
    # the flag gets used, which made the reliable path the least reliable one.
    it 'does not let --wait-for-regex match the echo of the text being sent' do
      start_session('s31', ['bash', '--norc', '-i'])
      # The documented pattern: wait for the child to be listening before
      # driving it. Sending into a still-booting shell also mixes its banner
      # into the reply, which is a different bug's territory.
      wait_until(reason: 'the shell prompt') { session('read', '--name=s31').data[:output].include?('$') }

      started = monotonic
      result = session('send', '--name=s31', '--settle-ms=6000', '--timeout-ms=20000',
                       '--wait-for-regex=MARKER', '--', 'sleep 2; echo MARKER')

      expect(result.data[:matched]).to be true
      # The echo arrives immediately; the real output only after the sleep.
      expect(monotonic - started).to be > 1.5
      expect(result.data[:output].scan('MARKER').length).to be >= 2
    end

    it 'caps the wait with --timeout-ms and reports it rather than failing' do
      start_session('s6', thinking_child(delay: 30))

      result = session('send', '--name=s6', '--settle-ms=200', '--timeout-ms=700', '--', 'slow')

      expect(result).to be_success
      expect(result.data[:timed_out]).to be true
      expect(result.data[:settled]).to be false
    end

    it 'returns immediately with --no-wait' do
      start_session('s7', thinking_child(delay: 30))

      result = session('send', '--name=s7', '--no-wait', '--', 'fire')

      expect(result.data[:sent]).to be true
      expect(result.data[:waited]).to be false
    end

    # PromptDetector only matches shell-shaped prompts, so for the agent CLIs
    # this feature exists to drive it is usually false. It must therefore stay
    # advisory: a send still returns normally with no prompt in sight.
    it 'reports prompt_detected as advisory metadata without gating the reply' do
      start_session('s8', thinking_child(delay: 0.1))

      result = session('send', '--name=s8', '--settle-ms=250', '--timeout-ms=15000', '--', 'no-prompt-here')

      expect(result).to be_success
      expect(result.data[:output]).to include('REPLY:no-prompt-here')
      expect(result.data[:prompt_detected]).to be false
    end
  end

  # Both of the following were found by driving a real agent CLI (grok), not by
  # reasoning about the code, and both made the feature silently useless
  # against exactly the targets it exists for. Pinned here so they cannot
  # regress unnoticed.
  describe 'driving a raw-mode TUI child' do
    # A raw-mode TUI reads keys itself and treats Enter as carriage return.
    # This child only acts on \r, so it fails outright if `send` terminates
    # with \n — which is how the real agent presented: the prompt sat unsent in
    # its composer while rune reported a clean settle.
    def carriage_return_child
      script = <<~CHILD
        require 'io/console'
        STDOUT.sync = true
        buffer = +''
        STDIN.raw do
          puts 'READY'
          loop do
            char = STDIN.getch
            break if char.nil?

            if char == "\\r"
              puts 'SUBMITTED:' + buffer
              buffer = +''
            else
              buffer << char
            end
          end
        end
      CHILD
      ['ruby', '-e', script]
    end

    it 'submits with a carriage return so a raw-mode child actually receives the line' do
      start_session('s21', carriage_return_child)
      # `start` returns once the supervisor is up, which is necessarily before
      # an arbitrary child has booted and put its terminal into raw mode. Send
      # before that and the still-cooked tty just echoes the input back, which
      # is precisely how this first failed.
      wait_until(reason: 'child to enter raw mode') do
        session('read', '--name=s21').data[:output].include?('READY')
      end

      result = session('send', '--name=s21', '--settle-ms=300', '--timeout-ms=15000', '--', 'typed')

      expect(result.data[:output]).to include('SUBMITTED:typed')
    end

    it 'gives the child a usable window size instead of leaving the pty at 0x0' do
      reporter = ['ruby', '-e',
                  "require 'io/console'; STDOUT.sync = true; puts 'SIZE:' + STDIN.winsize.inspect; STDIN.gets"]
      start_session('s22', reporter)

      wait_until(reason: 'child to report its window size') do
        session('read', '--name=s22').data[:output].include?('SIZE:')
      end
      expect(session('read', '--name=s22').data[:output])
        .to include("SIZE:[#{Rune::Session::Supervisor::DEFAULT_ROWS}, #{Rune::Session::Supervisor::DEFAULT_COLUMNS}]")
    end
  end

  # `rune run` has always returned an ANSI-stripped `clean_output` beside the
  # raw text. Sessions originally returned only raw output, which meant anyone
  # driving a full-screen TUI agent had to write their own ANSI stripper before
  # they could read a reply — the gap that made a shell one-liner insufficient.
  describe 'clean_output parity with rune run' do
    def ansi_child
      script = <<~CHILD
        STDOUT.sync = true
        while STDIN.gets
          puts "\e[32mGREEN\e[0m plain"
        end
      CHILD
      ['ruby', '-e', script]
    end

    it 'returns both raw and ANSI-stripped output from send' do
      start_session('s23', ansi_child)

      data = session('send', '--name=s23', '--settle-ms=250', '--timeout-ms=15000', '--', 'go').data

      expect(data[:output]).to include("\e[32m")
      expect(data[:clean_output]).to include('GREEN plain')
      expect(data[:clean_output]).not_to include("\e[32m")
    end

    it 'returns ANSI-stripped output from read as well' do
      start_session('s24', ansi_child)
      session('send', '--name=s24', '--settle-ms=250', '--timeout-ms=15000', '--', 'go')

      data = session('read', '--name=s24').data

      expect(data[:clean_output]).to include('GREEN plain')
      expect(data[:clean_output]).not_to include("\e[32m")
    end
  end

  # Found by an independent review (agy) driven through rune itself, then
  # reproduced before being fixed.
  describe 'a caller that goes away mid-send' do
    it 'releases the in-flight send instead of locking the session for the whole timeout' do
      start_session('s28', thinking_child(delay: 30))

      # Speak the control protocol directly so the caller can be abandoned the
      # way a killed or cancelled `rune session send` process abandons it.
      socket = Rune::Session::Store.with_bindable_path(store.socket_path('s28')) do |path|
        UNIXSocket.new(path)
      end
      socket.puts(JSON.generate(op: 'send', text: 'hello', settle_ms: 500, timeout_ms: 60_000))
      socket.flush
      wait_until(reason: 'the send to be in flight') do
        session('send', '--name=s28', '--settle-ms=100', '--timeout-ms=2000', '--', 'probe').failure?
      end
      socket.close

      # Without noticing the disconnect the supervisor holds @pending for the
      # full 60s and refuses every later send.
      wait_until(timeout: 20, reason: 'the session to accept sends again') do
        session('send', '--name=s28', '--settle-ms=100', '--timeout-ms=1500', '--', 'after').success?
      end
    end

    it 'survives a control client that connects and never completes a request line' do
      start_session('s29', thinking_child(delay: 0.1))
      partial = Rune::Session::Store.with_bindable_path(store.socket_path('s29')) do |path|
        UNIXSocket.new(path)
      end
      partial.write('{"op":"sen') # no newline, never finished
      partial.flush

      # A blocking `gets` here would freeze the only thread, stalling the pty
      # and every other request with it.
      begin
        expect(session('send', '--name=s29', '--settle-ms=250', '--timeout-ms=15000', '--', 'still-alive'))
          .to be_success
      ensure
        partial.close
      end
    end
  end

  describe 'read' do
    it 'serves the transcript from disk, including after the session is stopped' do
      start_session('s9', thinking_child(delay: 0.1))
      session('send', '--name=s9', '--settle-ms=250', '--timeout-ms=15000', '--', 'recorded')
      session('stop', '--name=s9')

      result = session('read', '--name=s9')

      expect(result).to be_success
      expect(result.data[:output]).to include('REPLY:recorded')
    end

    # `--since` is caller-supplied, so unlike the supervisor's own cursor it can
    # land mid-character. Found by dogfooding: reading a real agent's transcript
    # with --since died with a bare "invalid byte sequence in UTF-8", and a TUI
    # agent's transcript is never pure ASCII.
    it 'survives a --since offset that lands inside a multi-byte character' do
      multibyte = ['ruby', '-e', "STDOUT.sync = true; while STDIN.gets; puts '→ ünïcode ✓'; end"]
      start_session('s25', multibyte)
      session('send', '--name=s25', '--settle-ms=250', '--timeout-ms=15000', '--', 'go')
      full = session('read', '--name=s25').data[:output]
      arrow = full.index('→')
      skip 'child produced no multi-byte output' unless arrow

      result = session('read', '--name=s25', "--since=#{full.byteslice(0, arrow + 1).bytesize}")

      expect(result).to be_success
      expect(result.data[:output]).to be_valid_encoding
    end

    it 'honours --since so a caller can page from a prior cursor' do
      start_session('s10', thinking_child(delay: 0.1))
      first = session('send', '--name=s10', '--settle-ms=250', '--timeout-ms=15000', '--', 'alpha')
      session('send', '--name=s10', '--settle-ms=250', '--timeout-ms=15000', '--', 'beta')

      result = session('read', '--name=s10', "--since=#{first.data[:cursor]}")

      expect(result.data[:output]).to include('REPLY:beta')
      expect(result.data[:output]).not_to include('REPLY:alpha')
    end
  end

  # The agent-facing half of a session is send/read; this is the half that makes
  # a named session something a human can come back to — take the wheel on a
  # live agent, then leave it running exactly where it was.
  describe 'attach' do
    def attach_to(name)
      in_reader, in_writer = IO.pipe
      out_reader, out_writer = IO.pipe
      attachment = Rune::Session::Attachment.new(
        store.socket_path(name), input: in_reader, output: out_writer, announce: nil
      )
      seen = +''
      collector = Thread.new do
        loop { seen << out_reader.readpartial(4096) }
      rescue IOError, SystemCallError
        nil
      end
      worker = Thread.new { attachment.run }
      [in_writer, worker, collector, -> { seen }]
    end

    it 'replays the current screen, forwards keystrokes, and detaches without stopping the session' do
      start_session('s26', ['bash', '--norc', '-i'])
      session('send', '--name=s26', '--settle-ms=300', '--timeout-ms=15000', '--', 'echo BEFORE_ATTACH')

      writer, worker, collector, seen = attach_to('s26')
      begin
        # Backlog replay: an attaching terminal lands on a populated screen.
        wait_until(reason: 'attach backlog') { seen.call.include?('BEFORE_ATTACH') }

        writer.write("echo FROM_ATTACHED\r")
        wait_until(reason: 'typed line to reach the child') { seen.call.include?('FROM_ATTACHED') }

        writer.write("\x1d") # Ctrl-]
        result = worker.value

        expect(result).to be_success
        expect(result.data[:detached]).to be true
      ensure
        collector.kill
        worker.kill if worker.alive?
      end

      # Detaching must leave the child running — that is the whole difference
      # between this and `rune watch`, which owns the child it spawned.
      expect(session('list').data[:sessions].first[:state]).to eq('running')
      expect(session('send', '--name=s26', '--settle-ms=300', '--timeout-ms=15000', '--', 'echo STILL_HERE')
               .data[:output]).to include('STILL_HERE')
    end

    it 'refuses to attach to a session that is not running' do
      start_session('s27', ['bash', '--norc', '-i'])
      session('stop', '--name=s27')

      expect(session('attach', '--name=s27')).to be_failure
    end
  end

  describe 'lifecycle' do
    it 'reports running, then stopped, and leaves no orphan process' do
      start_session('s11', ['bash', '--norc', '-i'])
      meta = store.read_meta('s11')
      expect(session('list').data[:sessions].first[:state]).to eq('running')

      session('stop', '--name=s11')

      wait_until(reason: 'child and supervisor to exit') do
        [meta[:child_pid], meta[:supervisor_pid]].none? { |pid| Rune::Session::Store.alive?(pid) }
      end
      expect(session('list').data[:sessions].first[:state]).to eq('stopped')
    end

    it 'treats stop as idempotent' do
      start_session('s12', ['bash', '--norc', '-i'])
      session('stop', '--name=s12')

      expect(session('stop', '--name=s12')).to be_success
    end

    it 'reports a supervisor that died without cleanup as dead, not as running' do
      start_session('s13', ['bash', '--norc', '-i'])
      meta = store.read_meta('s13')
      # SIGKILL specifically: the supervisor never gets to update meta.json, so
      # the recorded state stays "running" and only a real liveness check can
      # tell the truth.
      Process.kill('KILL', meta[:supervisor_pid])
      wait_until(reason: 'supervisor to die') { !Rune::Session::Store.alive?(meta[:supervisor_pid]) }

      expect(session('list').data[:sessions].first[:state]).to eq('dead')
    end

    # A `start` that fails after spawning must not leave the supervisor it
    # spawned holding a pty for a session the caller was just told does not
    # exist. Found by checking for stray processes after an unrelated failure,
    # so it is pinned here rather than left to the next accident.
    it 'kills the supervisor it spawned when the session never becomes ready' do
      allow_any_instance_of(described_class).to receive(:await_ready).and_return('forced not-ready')

      result = session('start', '--name=s20', '--', 'bash', '--norc', '-i')
      expect(result).to be_failure

      meta = store.read_meta('s20') || {}
      wait_until(reason: 'abandoned supervisor to die') do
        [meta[:child_pid], meta[:supervisor_pid]].compact.none? { |pid| Rune::Session::Store.alive?(pid) }
      end
    end

    # Also from agy's review: without a liveness check `start` waited out the
    # full START_TIMEOUT for an answer that was already certain.
    it 'fails fast when the supervisor dies before reporting ready, rather than waiting out the timeout' do
      corpse = Process.spawn('true')
      Process.wait(corpse)
      allow_any_instance_of(described_class).to receive(:spawn_supervisor).and_return(corpse)

      started = monotonic
      result = session('start', '--name=s30', '--', 'bash', '--norc', '-i')

      expect(result).to be_failure
      expect(result.error).to include('supervisor exited')
      expect(monotonic - started).to be < (described_class::START_TIMEOUT / 2)
    end

    it 'records the exit and stops supervising when the child exits on its own' do
      start_session('s14', ['bash', '--norc', '-c', 'exit 7'])

      wait_until(reason: 'session to record its exit') do
        (store.read_meta('s14') || {})[:state] == 'exited'
      end
      expect(store.read_meta('s14')[:exit_code]).to eq(7)
    end
  end

  describe 'naming, project scope, and archiving' do
    it 'generates a <tool>-<word> codename when --name is omitted' do
      result = session('start', '--', 'bash', '--norc', '-i')

      expect(result).to be_success
      expect(result.data[:name]).to match(/\Abash-[a-z]+\z/)
    end

    it 'gives concurrently started sessions of the same tool distinct names' do
      first = session('start', '--', 'bash', '--norc', '-i').data[:name]
      second = session('start', '--', 'bash', '--norc', '-i').data[:name]

      expect(first).not_to eq(second)
    end

    # A name only means something inside a scope. Without this, `reviewer` in
    # one checkout and `reviewer` in another are the same session, and you can
    # reach the wrong agent from the wrong directory.
    it 'scopes sessions to a project so the same name in another project is a different session' do
      start_session('scoped', ['bash', '--norc', '-i'])
      other = Rune::Session::Store.new(home: @home, project: 'someplace-else')

      expect(store.names).to include('scoped')
      expect(other.names).to be_empty
    end

    it 'derives the project from the enclosing git working tree' do
      Dir.mktmpdir do |repo|
        FileUtils.mkdir_p(File.join(repo, '.git'))
        nested = File.join(repo, 'a', 'b')
        FileUtils.mkdir_p(nested)

        expect(Rune::Session::Store.project_root(nested)).to eq(Rune::Session::Store.project_root(repo))
      end
    end

    it 'archives a stopped session so its name is free and it is no longer listed as live' do
      start_session('recycle', ['bash', '--norc', '-i'])
      session('send', '--name=recycle', '--settle-ms=250', '--timeout-ms=15000', '--', 'echo OLD_LIFETIME')
      session('stop', '--name=recycle')

      expect(session('archive', '--name=recycle')).to be_success
      expect(session('list').data[:sessions]).to be_empty
      expect(session('list', '--archived').data[:sessions].first[:name]).to include('recycle')

      # The freed name must start clean, not resurrect the archived transcript.
      start_session('recycle', ['bash', '--norc', '-i'])
      expect(session('read', '--name=recycle').data[:output]).not_to include('OLD_LIFETIME')
    end

    it 'refuses to archive a session that is still running' do
      start_session('busy', ['bash', '--norc', '-i'])

      result = session('archive', '--name=busy')

      expect(result).to be_failure
      expect(result.error).to include('still running')
    end
  end

  # "Is it working or is it stuck, and what was it last doing" is the question
  # when several agents run at once, and the transcript already answers it.
  describe 'activity reporting' do
    it 'reports idle time and the last meaningful line for each session' do
      start_session('busywork', thinking_child(delay: 0.1))
      session('send', '--name=busywork', '--settle-ms=250', '--timeout-ms=15000', '--', 'marker')

      entry = session('list').data[:sessions].first

      expect(entry[:idle_ms]).to be_a(Integer)
      expect(entry[:last_line]).to include('REPLY:marker')
    end

    # last_line exists to be read at a glance, which it is not if a full-screen
    # agent's escape traffic survives into it.
    it 'strips terminal escape sequences out of the reported last line' do
      noisy = ['ruby', '-e',
               'STDOUT.sync = true; while STDIN.gets; print "\\e[?25h\\e]0;t\\a\\e[32mVISIBLE\\e[0m\\n"; end']
      start_session('noisy', noisy)
      session('send', '--name=noisy', '--settle-ms=250', '--timeout-ms=15000', '--', 'go')

      last = session('list').data[:sessions].first[:last_line]

      expect(last).to include('VISIBLE')
      expect(last).not_to include("\e")
    end
  end

  describe 'process teardown' do
    # Also from grok's review: agent CLIs spawn workers (node wrappers, MCP
    # servers). Signalling only the recorded child pid left those running after
    # `stop`, holding ptys and ports.
    it 'kills the child process group so its own children do not survive stop' do
      spawner = <<~'CHILD'
        STDOUT.sync = true
        worker = spawn('sleep 300')
        puts "WORKER:#{worker}"
        sleep 300
      CHILD
      start_session('s32', ['ruby', '-e', spawner])
      wait_until(reason: 'the grandchild pid to be reported') do
        session('read', '--name=s32').data[:output].to_s.include?('WORKER:')
      end
      worker_pid = session('read', '--name=s32').data[:output][/WORKER:(\d+)/, 1].to_i

      session('stop', '--name=s32')

      wait_until(reason: 'the grandchild to die with its group') do
        !Rune::Session::Store.alive?(worker_pid)
      end
    end
  end

  describe 'state on disk' do
    it 'creates owner-only directories and files' do
      start_session('s15', ['bash', '--norc', '-i'])

      expect(File.stat(store.session_dir('s15')).mode & 0o777).to eq(0o700)
      expect(File.stat(store.meta_path('s15')).mode & 0o777).to eq(0o600)
      expect(File.stat(store.output_path('s15')).mode & 0o777).to eq(0o600)
    end

    it 'writes a transcript using the same NDJSON event vocabulary as rune watch' do
      start_session('s16', thinking_child(delay: 0.1))
      session('send', '--name=s16', '--settle-ms=250', '--timeout-ms=15000', '--', 'logged')

      events = File.readlines(store.output_path('s16')).map { |line| JSON.parse(line) }
      expect(events.first).to include('event' => 'start')
      expect(events.map { |event| event['event'] }).to include('output')
      expect(events).to all(include('ts'))
    end
  end

  describe 'argument handling' do
    it 'accepts --name NAME as well as --name=NAME' do
      start_session('s17', ['bash', '--norc', '-i'])

      expect(session('send', '--name', 's17', '--settle-ms', '300', '--', 'echo spaced').data[:output])
        .to include('spaced')
    end

    it 'rejects an invalid session name before spawning anything' do
      result = session('start', '--name=../escape', '--', 'bash')

      expect(result).to be_failure
      expect(result.error).to include('Invalid session name')
    end

    it 'refuses to start a second session under a running name' do
      start_session('s18', ['bash', '--norc', '-i'])

      result = session('start', '--name=s18', '--', 'bash')

      expect(result).to be_failure
      expect(result.error).to include('already running')
    end

    it 'returns a structured failure for an unknown session' do
      expect(session('send', '--name=nope', '--', 'hi')).to be_failure
    end

    it 'rejects an invalid --wait-for-regex before sending anything' do
      start_session('s19', ['bash', '--norc', '-i'])

      result = session('send', '--name=s19', '--wait-for-regex=[unclosed', '--', 'hi')

      expect(result).to be_failure
      expect(result.error).to include('Invalid --wait-for-regex')
    end

    it 'returns a structured failure for an unknown subcommand' do
      expect(session('bogus')).to be_failure
    end
  end

  describe 'agent mode end to end' do
    it 'emits stdout that parses as a single JSON document through the real executable' do
      executable = File.expand_path('../../bin/rune', __dir__)
      env = { 'RUNE_HOME' => @home }
      start_out, start_status = Open3.capture2(env, executable, 'session', 'start', '--name=e2e',
                                               '--json', '--', 'bash', '--norc', '-i')
      send_out, = Open3.capture2(env, executable, 'session', 'send', '--name=e2e',
                                 '--settle-ms=300', '--timeout-ms=15000', '--json', '--', 'echo end-to-end')

      expect(start_status).to be_success
      expect { JSON.parse(start_out) }.not_to raise_error
      expect(JSON.parse(send_out).dig('data', 'output')).to include('end-to-end')
    end
  end
end
