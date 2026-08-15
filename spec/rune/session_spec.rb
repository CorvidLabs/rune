# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'socket'
require 'fileutils'
require 'stringio'

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

  # The limitations CHG-0030 closes. Each was documented as a known gap before
  # being fixed, so these pin the new behaviour rather than the old caveat.
  describe 'no single peer can wedge the supervisor' do
    it 'stays responsive while a child that never reads stdin is written to' do
      deaf = ['ruby', '-e', "STDOUT.sync = true; puts 'READY'; sleep 300"]
      start_session('s33', deaf)
      wait_until(reason: 'child ready') { session('read', '--name=s33').data[:output].include?('READY') }

      # Large enough to exceed any pty input buffer. A blocking write here used
      # to be able to stop the only thread, taking pty pumping and settle
      # evaluation down with it.
      session('send', '--name=s33', '--no-wait', '--', 'x' * 200_000)

      expect(session('list').data[:sessions].first[:state]).to eq('running')
      expect(session('stop', '--name=s33')).to be_success
    end

    it 'reaps control connections that connect and never send' do
      start_session('s34', ['bash', '--norc', '-i'])
      path = store.socket_path('s34')
      idle = 30.times.filter_map do
        Rune::Session::Store.with_bindable_path(path) { |p| UNIXSocket.new(p) }
      rescue SystemCallError
        nil
      end
      expect(idle).not_to be_empty

      # Silent peers are never readable, so they were never examined and stayed
      # in the client set for the life of the session.
      wait_until(timeout: 20, reason: 'idle connections to be dropped') do
        idle.all? do |socket|
          socket.wait_readable(0) && socket.eof?
        rescue StandardError
          true
        end
      end
      expect(session('send', '--name=s34', '--settle-ms=300', '--timeout-ms=15000', '--', 'echo ok')
               .data[:output]).to include('ok')
    ensure
      idle&.each do |socket|
        socket.close
      rescue StandardError
        nil
      end
    end
  end

  # Round-2 review findings (agy), all in the write-queue work itself. These are
  # deliberately white-box: the end-to-end versions passed against the unfixed
  # code because filling a socket buffer on demand is not reliable, and a test
  # that cannot fail against the bug it names is worse than no test.
  describe 'write-queue bookkeeping' do
    let(:supervisor) do
      Rune::Session::Supervisor.new(name: 'unit', command: ['true'], store: store)
    end

    it 'unregisters a closed IO everywhere, so it can never reach IO.select' do
      reader, writer = IO.pipe
      supervisor.instance_variable_get(:@outbox)[writer] << 'queued'
      supervisor.instance_variable_get(:@attached) << writer
      supervisor.instance_variable_get(:@clients) << writer
      supervisor.instance_variable_get(:@accepted_at)[writer] = 0

      supervisor.send(:safe_close, writer)

      # A closed descriptor left in any of these reaches the next IO.select,
      # which raises IOError — unhandled, so the supervisor dies and its
      # teardown SIGKILLs a healthy child.
      expect(supervisor.instance_variable_get(:@outbox)).not_to have_key(writer)
      expect(supervisor.instance_variable_get(:@attached)).not_to include(writer)
      expect(supervisor.instance_variable_get(:@clients)).not_to include(writer)
      expect(supervisor.instance_variable_get(:@accepted_at)).not_to have_key(writer)
      reader.close
    end

    it 'treats a failed write to the pty master as the child exiting, not as a dead terminal' do
      reader, master = IO.pipe
      supervisor.instance_variable_set(:@writer, master)

      supervisor.send(:drop_writer, master)

      # `enqueue` used to call `flush_outbox` without the writer, so a failed
      # pty write was mistaken for a terminal going away: the master was closed
      # and @child_finished stayed false, leaving the in-flight send to wait out
      # its entire timeout instead of reporting the exit.
      expect(supervisor.instance_variable_get(:@child_finished)).to be true
      [reader, master].each do |io|
        io.close
      rescue IOError
        nil
      end
    end

    it 'registers an attaching terminal only after every fallible step has succeeded' do
      source = File.read('lib/rune/session/supervisor.rb')
      body = source[/def handle_attach.*?\n      end/m]

      # Ordering is the fix: an exception between the push and the end of setup
      # used to leave a closed socket in @attached.
      expect(body.index('resize_child')).to be < body.index('@attached << client')
    end

    # The ceiling exists for a terminal that attaches and stops reading. Applied
    # to every non-master IO it also hit control replies, and a settle answers
    # with the whole captured slice — so one long turn from a TUI agent was
    # thrown away and the caller told the session was unreachable.
    it 'never drops a control reply for exceeding the undrained-output ceiling' do
      client, peer = UNIXSocket.pair
      oversized = 'x' * (Rune::Session::Supervisor::MAX_OUTBOX_BYTES + 1024)

      supervisor.send(:respond, client, output: oversized)

      expect(client).not_to be_closed
      expect(supervisor.instance_variable_get(:@outbox)).to have_key(client)
      [client, peer].each { |io| io.close unless io.closed? }
    end

    it 'still drops an attached terminal that stops draining' do
      terminal, peer = UNIXSocket.pair
      supervisor.instance_variable_get(:@attached) << terminal

      supervisor.send(:enqueue, terminal, 'x' * (Rune::Session::Supervisor::MAX_OUTBOX_BYTES + 1024))

      expect(terminal).to be_closed
      expect(supervisor.instance_variable_get(:@attached)).not_to include(terminal)
      peer.close unless peer.closed?
    end

    # write_nonblock takes at most one socket buffer (~8 KiB on macOS), so a
    # large reply is still half in @outbox when the loop exits. The process then
    # died with the answer in its memory and the caller blocked on a newline the
    # kernel discarded.
    it 'pushes a partly-written reply out before teardown drops the socket' do
      client, peer = UNIXSocket.pair
      payload = 'y' * (512 * 1024)
      reader = Thread.new { peer.gets }

      supervisor.send(:respond, client, output: payload)
      supervisor.send(:cleanup, nil)
      client.close unless client.closed? # what process exit does

      expect(reader.join(10)).not_to be_nil
      expect(JSON.parse(reader.value, symbolize_names: true)[:output]).to eq(payload)
      peer.close unless peer.closed?
    end

    # `enqueue` reports a dead master by setting @child_finished rather than
    # raising, which left handle_send's own rescue unreachable. A waiting send
    # is still caught by resolve_pending; --no-wait had no such check and
    # answered `sent: true` for bytes that reached nothing.
    it 'reports a --no-wait send as failed when the write to the pty died' do
      read_end, master = IO.pipe
      read_end.close
      supervisor.instance_variable_set(:@writer, master)
      client, peer = UNIXSocket.pair

      supervisor.send(:handle_send, { text: 'hi', no_wait: true }, client, master)

      expect(JSON.parse(peer.gets, symbolize_names: true)[:error]).to match(/exited/)
      [client, peer, master].each { |io| io.close unless io.closed? }
    end
  end

  describe 'echo tracking with multibyte output' do
    let(:supervisor) do
      Rune::Session::Supervisor.new(name: 'unit', command: ['true'], store: store)
    end

    # Found by driving agy: the supervisor died reproducibly within a few turns,
    # taking the agent with it. An agent TUI paints spinners and box-drawing
    # rules, so multibyte output inside the echo grace window is the norm, not
    # an edge case.
    it 'does not raise when the arriving slice is multibyte' do
      expect { supervisor.send(:echo_still_arriving?, '⣟', 'run the command') }.not_to raise_error
    end

    it 'reports a multibyte slice that is not the echo as not-the-echo' do
      expect(supervisor.send(:echo_still_arriving?, '⣟⣯⣷', 'hello')).to be false
    end

    # Advancing past the echo by its byte length overshoots for non-ASCII, which
    # silently ate the first characters of the reply.
    it 'strips exactly the echo when the sent text was not ASCII' do
      supervisor.instance_variable_set(:@pending, { echo: 'héllo', sent_at: 0 })

      expect(supervisor.send(:beyond_echo, 'hélloANSWER')).to eq('ANSWER')
    end
  end

  describe 'submitting a line to a raw-mode child' do
    # Reports each read as its own chunk, so the test can see whether the
    # terminator arrived in the same read as the text. Raw mode is the point: a
    # cooked tty would not deliver anything until the line was complete, which
    # is exactly why this bug only affected raw-mode agent TUIs.
    # Reports the *shape* of each read rather than echoing its bytes: writing a
    # carriage return back out would move the cursor and make the transcript
    # unreadable, which is what the first version of this test did.
    def chunk_reporting_child
      script = <<~CHILD
        require 'io/console'
        STDOUT.sync = true
        STDIN.raw!
        print 'RAW-READY'
        loop do
          chunk = STDIN.readpartial(4096)
          print "[len=" + chunk.bytesize.to_s + ",cr=" + chunk.count("\\r").to_s + "]"
        end
      CHILD
      ['ruby', '-e', script]
    end

    # Sending before the child has switched its tty to raw mode measures the
    # line discipline instead: cooked mode holds the text until a terminator
    # arrives and then delivers both as one line, which looks exactly like the
    # bug. Real callers have the same race, which is why the docs say to wait
    # for the callee to be listening.
    def start_raw_child(name)
      start_session(name, chunk_reporting_child)
      wait_until(reason: 'the child to enter raw mode') do
        session('read', "--name=#{name}").data[:output].include?('RAW-READY')
      end
    end

    # Agent TUIs treat a large chunk arriving in one read as a paste, and a
    # carriage return inside a paste is a newline in the composer rather than
    # Enter. Measured against Claude Code, every input of ~64 characters or more
    # was typed and never sent while rune reported a clean settle — and an agent
    # prompt is almost always longer than that. 61 chars submitted, 82 did not;
    # after the fix all of 61..262 submit, on claude, grok and agy alike.
    it 'writes the terminator as a read separate from the text' do
      start_raw_child('sub1')

      session('send', '--name=sub1', '--settle-ms=400', '--timeout-ms=15000',
              '--', 'a prompt long enough that a TUI would call it a paste')
      reported = session('read', '--name=sub1').data[:output].scan(/\[len=(\d+),cr=(\d+)\]/)
      chunks = reported.map { |length, returns| { length: length.to_i, returns: returns.to_i } }

      # The carriage return arrives as a read of its own...
      expect(chunks).to include({ length: 1, returns: 1 })
      # ...and never in the same read as the text, which is what a TUI mistakes
      # for a pasted newline.
      expect(chunks.select { |chunk| chunk[:returns].positive? }.map { |chunk| chunk[:length] }).to all(eq(1))
    end

    it 'still sends nothing extra with --no-newline' do
      start_raw_child('sub2')

      session('send', '--name=sub2', '--no-wait', '--no-newline', '--', 'bare')
      wait_until(reason: 'the text to arrive') { session('read', '--name=sub2').data[:output].include?('[len=4') }

      expect(session('read', '--name=sub2').data[:output]).not_to include('cr=1')
    end
  end

  describe 'a --wait-for-regex that backtracks catastrophically' do
    # Matching runs on the supervisor's only thread, so a pattern that
    # backtracks blocks the loop: it cannot pump the pty, cannot answer `stop`,
    # and cannot even check the send's own --timeout-ms. Reproduced against a
    # child emitting 60 a's, where the send was still blocked long after its 8s
    # deadline. Ruby memoizes most textbook cases since 3.2, but not patterns
    # using backreferences — which is the shape that got through.
    let(:babbling_child) do
      ['ruby', '-e', 'STDOUT.sync = true; while (line = STDIN.gets); puts("a" * 60 + "b"); end']
    end

    # Ruby 3.0 and 3.1 have no per-Regexp timeout, so there is nothing to assert
    # there beyond the documented limitation.
    before { skip 'Regexp timeouts need Ruby 3.2+' unless Regexp.method_defined?(:timeout) }

    it 'abandons the pattern and answers, rather than wedging the loop past its own deadline' do
      start_session('redos1', babbling_child)

      started = monotonic
      result = session('send', '--name=redos1', '--wait-for-regex=(a+)+\1$',
                       '--settle-ms=500', '--timeout-ms=8000', '--', 'go')

      expect(result.data[:regex_timed_out]).to be true
      expect(monotonic - started).to be < 8
    end

    it 'leaves the session usable afterwards' do
      start_session('redos2', babbling_child)
      session('send', '--name=redos2', '--wait-for-regex=(a+)+\1$',
              '--settle-ms=500', '--timeout-ms=8000', '--', 'go')

      result = session('send', '--name=redos2', '--settle-ms=500', '--timeout-ms=15000', '--', 'again')

      expect(result.data[:settled]).to be true
    end
  end

  describe 'read --screen' do
    # A child shaped like a full-screen agent: it repaints a status line many
    # times, then leaves an answer. The byte stream holds every frame; the
    # screen holds what the terminal is actually showing.
    def repainting_child
      script = <<~CHILD
        STDOUT.sync = true
        while (line = STDIN.gets)
          10.times { |i| print "\\rthinking \#{i}s   " }
          print "\\r\\e[KANSWER:" + line.strip + "\\r\\n"
        end
      CHILD
      ['ruby', '-e', script]
    end

    it 'returns the rendered terminal alongside the byte stream' do
      start_session('scr1', repainting_child)
      session('send', '--name=scr1', '--settle-ms=400', '--timeout-ms=15000', '--', 'ping')

      result = session('read', '--name=scr1', '--screen')

      expect(result).to be_success
      expect(result.data[:screen]).to include('ANSWER:ping')
      # Every repaint frame survives in the stripped byte stream; only the last
      # one is on screen. That difference is the entire reason this exists.
      expect(result.data[:clean_output].scan('thinking').length).to be > 5
      expect(result.data[:screen].scan('thinking').length).to eq(0)
    end

    it 'omits the screen unless asked, so the default result shape is unchanged' do
      start_session('scr2', repainting_child)

      expect(session('read', '--name=scr2').data).not_to have_key(:screen)
    end

    # The primary case: one agent driving another wants the answer, and asking
    # for it in the same call is the difference between the fix being usable and
    # being a footnote.
    it 'returns the settled screen from send itself' do
      start_session('scr3', repainting_child)

      result = session('send', '--name=scr3', '--screen', '--settle-ms=400',
                       '--timeout-ms=15000', '--', 'pong')

      expect(result.data[:screen]).to include('ANSWER:pong')
      expect(result.data[:screen].scan('thinking').length).to eq(0)
    end

    it 'omits the screen from send unless asked' do
      start_session('scr4', repainting_child)

      result = session('send', '--name=scr4', '--settle-ms=400', '--timeout-ms=15000', '--', 'quiet')

      expect(result.data).not_to have_key(:screen)
    end
  end

  describe 'a send that lands while the child is still talking' do
    # The characteristic failure measured against a real agent CLI is not a
    # truncated answer: it is the *previous* turn's answer, whole and
    # well-formed, which the caller cannot distinguish from a correct reply.
    it 'flags a send issued while the previous turn was still producing output' do
      start_session('busy1', thinking_child(delay: 0.4))
      session('send', '--name=busy1', '--no-wait', '--', 'first')

      result = session('send', '--name=busy1', '--settle-ms=1500', '--timeout-ms=15000', '--', 'second')

      expect(result.data[:busy_at_send]).to be true
    end

    it 'does not flag a send into a quiet child' do
      start_session('busy2', thinking_child(delay: 0.1))
      session('send', '--name=busy2', '--settle-ms=400', '--timeout-ms=15000', '--', 'settle-first')

      result = session('send', '--name=busy2', '--settle-ms=400', '--timeout-ms=15000', '--', 'now-quiet')

      expect(result.data[:busy_at_send]).to be false
    end
  end

  describe 'a supervisor that dies unexpectedly' do
    # It used to leave meta saying "running" with no exit code and an empty
    # supervisor.log, so nothing anywhere named the cause.
    it 'records the crash and marks the session finished' do
      session_store = store
      supervisor = Rune::Session::Supervisor.new(name: 'crashy', command: ['true'], store: session_store)
      session_store.create('crashy')
      session_store.write_meta('crashy', name: 'crashy', command: ['true'], state: 'running')
      supervisor.instance_variable_set(:@output_log, session_store.open_output('crashy'))

      # `crashed` deliberately writes to stderr; capture it so a passing suite
      # does not print a crash report that looks like a real failure.
      original = $stderr
      $stderr = StringIO.new
      begin
        supervisor.send(:crashed, TypeError.new('boom'))
      ensure
        $stderr = original
      end

      meta = session_store.read_meta('crashy')
      expect(meta[:state]).to eq('exited')
      expect(meta[:exit_code]).to eq(Rune::Session::Supervisor::EXIT_SUPERVISOR_CRASHED)
      events = File.readlines(session_store.output_path('crashy')).map { |line| JSON.parse(line) }
      crash = events.find { |event| event['event'] == 'crash' }
      expect(crash['error']).to eq('TypeError')
      expect(crash['message']).to eq('boom')
    end
  end

  describe 'a start without --name' do
    # The lock serialises one name, but the name was picked before it: two
    # `start -- grok` racing each other both landed on the same codename, and
    # the loser failed on a name it never asked for while a dozen others were
    # free — the parallel-agent case an optional name exists for. The fixed
    # path picks inside the lock, so it also stops consulting generate_name
    # during the pre-flight check.
    it 'retries onto another codename when the one it picked is being claimed' do
      candidates = %w[taken-one taken-one taken-one open-one]
      allow_any_instance_of(Rune::Session::Store)
        .to receive(:generate_name) { candidates.shift || 'open-one' }
      FileUtils.mkdir_p(store.session_dir('taken-one'))
      result = File.open(store.lock_path('taken-one'), File::RDWR | File::CREAT, 0o600) do |holder|
        holder.flock(File::LOCK_EX)
        session('start', '--', 'bash', '--norc', '-i')
      end

      expect(result).to be_success
      expect(result.data[:name]).to eq('open-one')
    end
  end

  describe 'concurrent start of one name' do
    it 'lets exactly one win and leaves no orphaned supervisor' do
      results = 4.times.map { Thread.new { session('start', '--name=dup', '--', 'bash', '--norc', '-i') } }
                       .map(&:value)

      expect(results.count(&:success?)).to eq(1)
      expect(store.names).to eq(['dup'])
      # The losers must not have unlinked the winner's socket or left a child.
      expect(session('send', '--name=dup', '--settle-ms=300', '--timeout-ms=15000', '--', 'echo winner')
               .data[:output]).to include('winner')
    end
  end

  describe 'terminal size' do
    def size_reporter
      script = <<~'CHILD'
        require 'io/console'
        STDOUT.sync = true
        puts "SIZE:#{STDIN.winsize.inspect}"
        Signal.trap('WINCH') { puts "RESIZED:#{STDIN.winsize.inspect}" }
        sleep 300
      CHILD
      ['ruby', '-e', script]
    end

    it 'starts headless at the documented default' do
      start_session('s35', size_reporter)

      wait_until(reason: 'the child to report its size') do
        session('read', '--name=s35').data[:output].include?('SIZE:')
      end
      expect(session('read', '--name=s35').data[:output])
        .to include("SIZE:[#{Rune::Session::Supervisor::DEFAULT_ROWS}, #{Rune::Session::Supervisor::DEFAULT_COLUMNS}]")
    end

    it 'adopts an attaching terminal\'s size and restores the default on detach' do
      start_session('s36', size_reporter)
      wait_until(reason: 'the child to report its size') do
        session('read', '--name=s36').data[:output].include?('SIZE:')
      end

      in_reader, in_writer = IO.pipe
      out_reader, out_writer = IO.pipe
      # A pipe has no winsize, so stand in for a terminal that reports one.
      def in_reader.winsize = [50, 200]
      attachment = Rune::Session::Attachment.new(
        store.socket_path('s36'), input: in_reader, output: out_writer, announce: nil
      )
      worker = Thread.new { attachment.run }
      begin
        wait_until(reason: 'the child to see the attached size') do
          session('read', '--name=s36').data[:output].include?('RESIZED:[50, 200]')
        end
        in_writer.write("\x1d")
        worker.value
      ensure
        worker.kill if worker.alive?
        [in_reader, in_writer, out_reader, out_writer].each do |io|
          io.close
        rescue StandardError
          nil
        end
      end

      # Back to the headless default, so a later programmatic send renders the
      # same whether or not a human attached in between.
      wait_until(reason: 'the default size to be restored') do
        session('read', '--name=s36').data[:output]
                                     .include?("RESIZED:[#{Rune::Session::Supervisor::DEFAULT_ROWS}, " \
                                               "#{Rune::Session::Supervisor::DEFAULT_COLUMNS}]")
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
