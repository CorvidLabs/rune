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

  def session_command = described_class.new

  def session(*args)
    described_class.new.call(args.map(&:to_s), {})
  end

  # Runs a block as though the caller were in a different working directory, which is what a rune
  # project is. `Dir.chdir` is process-global, so the block is kept to the one call.
  def in_project(dirname, &block)
    Dir.mktmpdir do |root|
      other = File.join(root, dirname)
      Dir.mkdir(other)
      Dir.chdir(other, &block)
    end
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

  # Gap recording removed the old bound as a side effect. Before it, a rotation
  # that could not succeed closed the handle and every later write was silently
  # swallowed — ugly, but the cap held. Recording through the failure removed
  # the swallowing and with it the limit: measured against an unwritable
  # directory the transcript passed 42MB against a 32MB cap and kept climbing,
  # while the guide promised a session running for a day does not grow without
  # limit.
  describe 'the transcript bound when rotation cannot succeed' do
    def supervisor_at(bytes)
      supervisor = Rune::Session::Supervisor.allocate
      supervisor.instance_variable_set(:@output_log, StringIO.new)
      supervisor.instance_variable_set(:@name, 'ceiling')
      supervisor.instance_variable_set(:@log_bytes, bytes)
      supervisor.instance_variable_set(:@log_gap, nil)
      supervisor
    end

    it 'stops writing at the hard ceiling and records the bytes as gap' do
      supervisor = supervisor_at(Rune::Session::Supervisor::HARD_LOG_CEILING)

      supervisor.send(:log_event, 'output', bytes: 200, text: 'x' * 200)

      expect(supervisor.instance_variable_get(:@output_log).string).to be_empty
      expect(supervisor.instance_variable_get(:@log_gap)).to eq(200)
    end

    it 'writes normally below the ceiling' do
      supervisor = supervisor_at(0)

      supervisor.send(:log_event, 'output', bytes: 200, text: 'x' * 200)

      expect(supervisor.instance_variable_get(:@output_log).string).not_to be_empty
      expect(supervisor.instance_variable_get(:@log_gap)).to be_nil
    end
  end

  # Every one of these came from a field report driving grok and kimi through
  # rune on real work. Each is one additive field; each existed because the
  # information was already known and simply not said.
  # A socket client's most obvious mistake used to look like a hang: a send with
  # no text was accepted as an empty send, which writes a bare carriage return,
  # produces no output from most children, and so waits out timeout_ms — 120s by
  # default. Reported 3/3 against five-second client timeouts, alongside the
  # observation that every other malformed request got a clean error.
  describe 'a socket send with no text field' do
    it 'is refused immediately rather than waiting out the timeout' do
      start_session('sock', %w[cat])
      client = Rune::Session::Client.new(store.socket_path('sock'))

      reply = client.request({ op: 'send' })

      expect(reply[:error]).to include('text field')
    end

    it 'still accepts an empty string, which is the documented bare carriage return' do
      start_session('sock2', %w[cat])
      client = Rune::Session::Client.new(store.socket_path('sock2'))

      reply = client.request({ op: 'send', text: '', timeout_ms: 1500 })

      expect(reply[:error]).to be_nil
    end
  end

  describe 'saying what happened' do
    it 'reports the project a session registered in' do
      result = start_session('proj', %w[cat])

      # A session's namespace is the cwd's basename plus a hash, so every git
      # worktree is separate. Starting in a worktree and reading from the parent
      # repo gave "No such session", and `list` — the remedy the error suggests
      # — returned an empty array, confirming the wrong conclusion.
      expect(result.data[:project]).to eq(store.project)
    end

    it 'reports liveness on a send, so a loop cannot drive a corpse' do
      start_session('live', ['ruby', '-e', 'STDOUT.sync = true; STDIN.gets; exit 7'])

      session('send', '--name=live', '--settle-ms=300', '--timeout-ms=8000', '--', 'go')
      wait_until(reason: 'the child to exit') { session('list').data[:sessions].first[:state] == 'exited' }
      result = session('read', '--name=live')

      expect(result.data[:state]).to eq('exited')
      expect(result.data[:exit_code]).to eq(7)
    end

    it 'returns a cursor from --no-wait, so fire-and-poll is one call' do
      start_session('nw', %w[cat])

      result = session('send', '--name=nw', '--no-wait', '--', 'queued')

      expect(result.data[:cursor]).to be_a(Integer)
      expect(result.data[:waited]).to be false
    end

    # `--max-output` and `--tail` were parsed for every subcommand but applied
    # only by `read`. `send` is the call an agent makes most and the one whose
    # output is least bounded — a single turn of a full-screen TUI is megabytes —
    # so the flag that exists to bound it silently doing nothing there is the
    # worst place for it to be missing.
    it 'honours --max-output on send, not only on read' do
      start_session('cap', %w[cat])

      result = session('send', '--name=cap', '--settle-ms=300', '--timeout-ms=8000',
                       '--max-output=120', '--', 'X' * 4000)

      expect(result.data[:output].bytesize).to be <= 200
      expect(result.data[:truncated]).to be true
      expect(result.data[:omitted_bytes]).to be_positive
      expect(result.data[:clean_output]).to include('omitted by --max-output')
    end

    it 'honours --tail on send' do
      start_session('captail', %w[cat])

      result = session('send', '--name=captail', '--settle-ms=300', '--timeout-ms=8000',
                       '--tail=1', '--', 'one')

      expect(result.data[:truncated]).to be true
      expect(result.data[:omitted_lines]).to be_positive
    end

    # Bounding `output` and `clean_output` independently would let the two
    # describe different windows of one reply, and leave `omitted_bytes` true of
    # only one of them. `read` derives clean from the bounded raw; so does this.
    it 'derives clean_output from the bounded raw output, as read does' do
      start_session('capsame', %w[cat])

      result = session('send', '--name=capsame', '--settle-ms=300', '--timeout-ms=8000',
                       '--max-output=200', '--', 'Y' * 4000)

      expect(result.data[:clean_output])
        .to eq(Rune::Parsers::TextSanitizer.strip_ansi(result.data[:output]))
    end

    it 'refuses --max-output together with --tail, as rune run already does' do
      start_session('capboth', %w[cat])

      result = session('send', '--name=capboth', '--max-output=100', '--tail=3', '--', 'hi')

      expect(result.error).to include('Cannot combine --max-output and --tail')
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

    # Reports on SIGWINCH as well as at startup: a child that reads its winsize
    # before `apply_window_size` lands sees 0x0 and is corrected by the WINCH
    # that follows. See the 'terminal size' group for why that race exists.
    it 'gives the child a usable window size instead of leaving the pty at 0x0' do
      reporter = ['ruby', '-e',
                  "require 'io/console'; STDOUT.sync = true; " \
                  "Signal.trap('WINCH') { puts 'RESIZED:' + STDIN.winsize.inspect }; " \
                  "puts 'SIZE:' + STDIN.winsize.inspect; STDIN.gets"]
      start_session('s22', reporter)
      default = "[#{Rune::Session::Supervisor::DEFAULT_ROWS}, #{Rune::Session::Supervisor::DEFAULT_COLUMNS}]"

      wait_until(reason: 'child to report the default window size') do
        session('read', '--name=s22').data[:output].include?(default)
      end

      output = session('read', '--name=s22').data[:output]
      expect(output).to include("SIZE:#{default}").or include("RESIZED:#{default}")
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

  # Found by nine agents translating the README through rune, and the most
  # dangerous shape this project has: a reply that was well-formed and wrong.
  # `strip_ansi` only matches sequences that *terminated*, so a sequence split
  # across two pty reads left `clean_output` claiming the child printed text it
  # never displayed — and `screen`, in the same reply, disagreed.
  # `--tail` counted lines in the raw transcript, where CR is not a line break.
  # A full-screen TUI repaints with bare CRs and almost no LFs, so the flag that
  # exists to bound a reply matched nothing to trim and returned everything —
  # with `truncated` and `omitted_lines` absent, which reads as "nothing was
  # dropped". Measured against a live claude session, 84,945 bytes came back
  # identically for --tail=3, 5, 8, 12 and 20.
  # `--since` sliced the transcript and then handed the slice to a grep that ignored it and
  # searched the whole transcript, so a caller paging with `--since=<last cursor>` got the entire
  # history back on every page, under a `grep_matches` count that looked like it had filtered.
  describe '--grep together with --since' do
    def echoing_child
      ['ruby', '-e', 'STDOUT.sync = true; while (line = STDIN.gets); puts("SAW:" + line); end']
    end

    it 'greps only the slice the cursor selected' do
      start_session('gs1', echoing_child)
      session('send', '--name=gs1', '--settle-ms=400', '--timeout-ms=15000', '--', 'NEEDLE_ONE')
      cursor = session('read', '--name=gs1').data[:cursor]
      session('send', '--name=gs1', '--settle-ms=400', '--timeout-ms=15000', '--', 'NEEDLE_TWO')

      result = session('read', '--name=gs1', "--since=#{cursor}", '--grep=NEEDLE')

      expect(result.data[:clean_output]).to include('NEEDLE_TWO')
      expect(result.data[:clean_output]).not_to include('NEEDLE_ONE')
    end

    it 'still searches the whole transcript when no cursor was given' do
      start_session('gs2', echoing_child)
      session('send', '--name=gs2', '--settle-ms=400', '--timeout-ms=15000', '--', 'NEEDLE_ONE')
      session('send', '--name=gs2', '--settle-ms=400', '--timeout-ms=15000', '--', 'NEEDLE_TWO')

      result = session('read', '--name=gs2', '--grep=NEEDLE')

      expect(result.data[:clean_output]).to include('NEEDLE_ONE').and include('NEEDLE_TWO')
    end
  end

  describe '--tail against carriage-return repaint output' do
    def repainting_child
      ['ruby', '-e', 'STDOUT.sync = true; while STDIN.gets; print "l1\rl2\rl3\rl4\rl5\r"; end']
    end

    it 'counts a carriage return as a line break, so the bound actually applies' do
      start_session('tl1', repainting_child)
      session('send', '--name=tl1', '--settle-ms=400', '--timeout-ms=15000', '--', 'go')

      result = session('read', '--name=tl1', '--tail=2')

      expect(result.data[:truncated]).to be true
      expect(result.data[:omitted_lines]).to be_positive
      expect(result.data[:clean_output].lines.length).to be <= 2
    end

    it 'reports no truncation when the bound genuinely does not apply' do
      start_session('tl2', repainting_child)
      session('send', '--name=tl2', '--settle-ms=400', '--timeout-ms=15000', '--', 'go')

      result = session('read', '--name=tl2', '--tail=500')

      expect(result.data[:truncated]).to be_nil
      expect(result.data[:omitted_lines]).to be_nil
    end
  end

  describe 'an escape sequence split across two pty reads' do
    # Prints, opens a sequence, pauses long enough to be read mid-sequence, then
    # completes it. The pause is what makes the split deterministic.
    def split_escape_child(pause: 3)
      ['ruby', '-e',
       "STDOUT.sync = true; print \"READY\\n\"; print \"\\e[3\"; sleep #{pause}; " \
       'print "1mRED\\e[0m\\n"; sleep 30']
    end

    it 'does not deliver the fragment as visible text, and stops the cursor before it' do
      start_session('esc1', split_escape_child)
      wait_until(reason: 'the child to print and open a sequence') do
        session('read', '--name=esc1').data[:clean_output].to_s.include?('READY')
      end

      result = session('read', '--name=esc1')

      expect(result.data[:clean_output]).not_to include("\e")
      expect(result.data[:clean_output]).to include('READY')
      # 7 bytes of "READY\r\n", with the three-byte fragment withheld.
      expect(result.data[:cursor]).to eq(7)
    end

    it 'returns the completed sequence stripped, from the cursor the earlier read handed out' do
      start_session('esc2', split_escape_child)
      wait_until(reason: 'the child to print and open a sequence') do
        session('read', '--name=esc2').data[:clean_output].to_s.include?('READY')
      end
      cursor = session('read', '--name=esc2').data[:cursor]

      wait_until(reason: 'the child to complete the sequence') do
        session('read', '--name=esc2', "--since=#{cursor}").data[:clean_output].to_s.include?('RED')
      end
      result = session('read', '--name=esc2', "--since=#{cursor}", '--screen')

      expect(result.data[:clean_output]).to include('RED')
      expect(result.data[:clean_output]).not_to include('1mRED')
      # The whole point: the two fields in one reply must not contradict.
      expect(result.data[:screen]).to include('RED')
      expect(result.data[:screen]).not_to include('1mRED')
    end

    # `list` summarised the last event on its own, and a pty read boundary is
    # neither a line boundary nor a sequence boundary.
    it 'summarises list last_line from the reassembled tail, not one event' do
      start_session('esc3', split_escape_child)
      wait_until(reason: 'the child to complete the sequence') do
        session('read', '--name=esc3').data[:clean_output].to_s.include?('RED')
      end

      entry = session('list').data[:sessions].find { |s| s[:name] == 'esc3' }

      expect(entry[:last_line]).to eq('RED')
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
      expect(result.data[:output]).not_to include("\uFFFD")
      expect(result.data[:clean_output]).not_to include("\uFFFD")
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

  # A session started in one directory and read from another got "No such session", and the remedy
  # that error printed — `rune session list` — is scoped to the caller's own project and returns
  # nothing, which reads as proof the session died. Two people who had read the guide's warning
  # about directory scoping hit it anyway; one went off to debug the child.
  # `start` with a binary that is not on PATH returned status "ok" with exit_code 127, so a caller
  # checking the field whose job is to say whether the call worked saw success. It was documented
  # as "check state instead", which is the wrong shape of answer — an envelope should not need a
  # footnote to be read correctly. Reported from a real drive where it cost an hour.
  describe 'a launch that never happened' do
    it 'reports failure rather than success with a field to check' do
      result = session('start', '--name=ghost', '--', 'definitely_not_a_real_binary_xyz')

      expect(result).to be_failure
      expect(result.error).to include('127').and include('could not be executed')
    end

    # A child that exits 0 immediately launched fine and had nothing to do. Treating any prompt
    # exit as a failure would break every short-lived child.
    it 'still succeeds for a child that exits cleanly and at once' do
      expect(session('start', '--name=quick', '--', 'true')).to be_success
    end

    # The test used to be `exit_code == 127`, on the reasoning that 127 means "command not found"
    # and therefore that the child never ran. 127 is an ordinary status a program may choose, so a
    # script that ran perfectly well was told it was not installed. Measured before the fix with the
    # child appending to a file first: 12 of 12 executed, 7 of 12 were reported as not installed —
    # racy, since it turned on whether the child died before the supervisor recorded it as running.
    it 'succeeds for a child that runs and then chooses to exit 127' do
      Dir.mktmpdir do |dir|
        ran = File.join(dir, 'ran')
        script = File.join(dir, 'exits127.sh')
        File.write(script, "#!/bin/sh\necho ran >> #{ran}\nexit 127\n")
        FileUtils.chmod(0o755, script)

        results = Array.new(6) { |i| session('start', "--name=real127_#{i}", '--', script) }

        expect(results).to all(be_success)
        # Out of band: the child's own file, not the reply, proves it executed.
        # Waited for rather than read at once — `start` returns before the child
        # has necessarily run, so reading immediately raced the children and
        # failed under a loaded full-suite run while passing in isolation.
        wait_until(reason: 'all six children to record that they ran') do
          File.exist?(ran) && File.readlines(ran).size == 6
        end
      end
    end

    # EACCES means exec itself failed, so the child never ran — the same class as a missing binary.
    # This returned `status: "ok"` and only failed on the next send.
    it 'reports failure for a target that exists but cannot be executed' do
      Dir.mktmpdir do |dir|
        script = File.join(dir, 'noexec.sh')
        File.write(script, "#!/bin/sh\necho hi\n")
        FileUtils.chmod(0o644, script)

        result = session('start', '--name=noexec', '--', script)

        expect(result).to be_failure
        expect(result.error).to include('126').and include('could not be executed')
      end
    end

    # The record is kept deliberately. `start` failing loudly is the fix; deleting the transcript
    # that shows *why* would replace one quiet failure with another, and `list` reporting it as
    # exited with 127 is exactly the diagnosis a caller needs.
    it 'keeps the record visibly dead rather than deleting the evidence' do
      session('start', '--name=ghost2', '--', 'definitely_not_a_real_binary_xyz')

      entry = session('list').data[:sessions].find { |s| s[:name] == 'ghost2' }

      # `dead` rather than `exited`: the supervisor is abandoned with the launch, so what `list`
      # reports is a session whose supervisor is gone and whose child exited 127 — which is the
      # diagnosis, and is what the record is kept for.
      expect(entry[:exit_code]).to eq(127)
      expect(entry[:state]).not_to eq('running')
    end
  end

  describe 'a session that exists in another project' do
    it 'names the project it is in, rather than claiming it does not exist' do
      start_session('scoped', %w[cat])

      error = in_project('elsewhere') { session('read', '--name=scoped') }.error

      expect(error).to include('scoped').and include('another project').or include('exists in')
      expect(error).not_to include('No such session')
    end

    it 'points at a remedy that actually shows it' do
      start_session('scoped2', %w[cat])

      expect(in_project('elsewhere') { session('read', '--name=scoped2') }.error)
        .to include('--all-projects')
    end

    it 'keeps the plain message for a session that exists nowhere' do
      expect(session('read', '--name=neverexisted').error).to include('No such session')
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

    # Idle time only answers "is it stuck" if it is readable when the answer is
    # yes. A session blocked on an approval prompt for a day and a half rendered
    # `idle 2172m`, in the same dim grey as every healthy line, and sat there for
    # 36 hours. Minutes stop being a unit anyone converts at that scale.
    describe 'the idle figure a human reads' do
      def suffix(idle_ms, state: 'running')
        described_class.new.send(:idle_suffix, { idle_ms: idle_ms, state: state })
      end

      it 'switches to hours and days rather than printing thousands of minutes' do
        expect(suffix(45_000)).to include('idle 45s')
        expect(suffix(300_000)).to include('idle 5m')
        expect(suffix(5_400_000)).to include('idle 1.5h')
        expect(suffix(130_293_976)).to include('idle 36.2h')
        expect(suffix(400_000_000)).to include('idle 4.6d')
      end

      # Grey is the colour of "nothing to see here", which is the wrong thing to
      # say about the one line that means a session has been waiting on a human
      # since yesterday.
      it 'stops dimming a running session once its silence is worth noticing' do
        expect(suffix(60_000)).to include("\e[90m")
        expect(suffix(130_293_976)).to include("\e[33m")
      end

      # A stopped session's idle time is just how long ago it stopped.
      it 'leaves a stopped session dim however long it has been quiet' do
        expect(suffix(130_293_976, state: 'stopped')).to include("\e[90m")
        expect(suffix(130_293_976, state: 'stopped')).not_to include("\e[33m")
      end
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

  # Every value flag has both an inline and a separate form. `--context` was
  # missing from the alias table, so the separate form was unrecognised and
  # silently swallowed — the exact invocation the guide shows — while
  # `--context=3` worked. The same gap made errors name flags that do not
  # exist, such as `Invalid --tail-lines value`.
  describe 'value flags whose name is not their internal key' do
    def parsed(*argv)
      Rune::Commands::SessionCommand.new.send(:extract_options, argv)
    end

    it 'accepts the separate form of every aliased flag' do
      inline, = parsed('--context=3', '--tail=5', '--max-output=9')
      separate, separate_rest, = parsed('--context', '3', '--tail', '5', '--max-output', '9')

      expect(separate).to eq(inline)
      expect(separate_rest).to be_empty
      expect(separate[:context_lines]).to eq(3)
    end

    it 'names the flag the caller typed when rejecting its value' do
      _options, _rest, message = parsed('--tail=0')

      expect(message).to include('--tail')
      expect(message).not_to include('--tail-lines')
    end
  end

  describe 'echo tracking with multibyte output' do
    def pending(echo:, now: 0)
      Rune::Session::PendingSend.new(client: nil, cursor: 0, echo: echo, now: now,
                                     settle_ms: 800, timeout_ms: 15_000)
    end

    # `absorb` takes what is *new*, so what a pattern would see is the window it
    # has built up rather than a function of the slice handed in.
    def beyond(send, *arrivals, now: 0)
      arrivals.each { |text| send.absorb(text, now: now) }
      send.matchable
    end

    # Found by driving agy: the supervisor died reproducibly within a few turns,
    # taking the agent with it. An agent TUI paints spinners and box-drawing
    # rules, so multibyte output inside the echo grace window is the norm, not
    # an edge case.
    it 'does not raise when the arriving slice is multibyte' do
      expect { beyond(pending(echo: 'run the command'), '⣟') }.not_to raise_error
    end

    # `observe` used to pass `now: nil`, and the partial-echo guard read `if now
    # && ...` — so a nil clock skipped it and the half-arrived echo counted as a
    # reply. @saw_output latches, so one such tick was enough: the send then
    # settled on the caller's own words while the child was still thinking. A
    # pty delivers a long line in several reads, so this fired for any input
    # longer than one read.
    it 'does not count a partly-arrived echo as the child having answered' do
      send = pending(echo: 'sleep 3; printf DONE', now: 0)

      send.absorb('sleep 3; pri', now: 0.01)

      expect(send.outcome(now: 1.0, child_finished: false,
                          submitted: true, last_output_at: 0.01)).to be_nil
    end

    it 'still settles once something past the echo arrives' do
      send = pending(echo: 'sleep 3; printf DONE', now: 0)

      send.absorb('sleep 3; printf DONE\r\nDONE', now: 0.01)
      outcome = send.outcome(now: 1.0, child_finished: false,
                             submitted: true, last_output_at: 0.01)

      expect(outcome).to eq({ settled: true })
    end

    # Inside the echo grace window nothing is offered while the echo might still
    # be arriving, because a child drawing the input into a bordered composer
    # defeats the search and trips no partial test either — handing back the
    # whole slice there gave the pattern a screenful of the caller's own words.
    # Past the window it becomes ordinary output, which is why a tick with
    # nothing new in it is still a tick the send has to be given.
    it 'does not mistake a multibyte slice for a partly-arrived echo' do
      send = pending(echo: 'hello')

      expect(beyond(send, '⣟⣯⣷', now: 0)).to eq('')
      expect(beyond(send, '', now: 1.0)).to eq('⣟⣯⣷')
    end

    # Advancing past the echo by its byte length overshoots for non-ASCII, which
    # silently ate the first characters of the reply.
    it 'strips exactly the echo when the sent text was not ASCII' do
      expect(beyond(pending(echo: 'héllo'), 'hélloANSWER')).to eq('ANSWER')
    end

    # The echo does not arrive in one read either. Locating it against the
    # accumulated arrivals rather than against each read is what keeps a prompt
    # longer than one 4KB pty read from being handed to the pattern in pieces.
    it 'locates an echo that arrived across several reads' do
      send = pending(echo: 'run the long command')

      expect(beyond(send, 'run the ', 'long com', 'mand>> ANSWER')).to eq('>> ANSWER')
    end
  end

  # `--wait-for-regex` is only worth anything if the pattern cannot be satisfied
  # by the caller's own input coming back. Locating the echo by substring is
  # enough for a child that echoes verbatim and nothing else; every shape below
  # is one a real child produced, and every one of them defeats it.
  describe 'a pattern is never satisfied by the echo of the input' do
    def waiting(echo:, regex:, settle_ms: 30_000)
      Rune::Session::PendingSend.new(client: nil, cursor: 0, echo: echo, now: 0, settle_ms: settle_ms,
                                     timeout_ms: 30_000,
                                     regex: Rune::Session::PendingSend.compile_regex(regex))
    end

    # One tick per arrival, the way the supervisor drives it: absorb what came
    # in, then ask. Stops at the first answer, because a settled send is not
    # given any more.
    def resolve(send, *arrivals, now: 1.0)
      arrivals.each do |text|
        send.absorb(text, now: now)
        outcome = send.outcome(now: now, child_finished: false, submitted: true, last_output_at: now)
        return outcome if outcome
      end
      nil
    end

    # python3 -q, captured verbatim: the REPL redraws the line on every
    # keystroke and colours each token separately, so the input is on the wire
    # dozens of times over and not once as the run of bytes being looked for.
    it 'ignores a REPL that repaints the line on every keystroke' do
      echo = "print('PYDONE')"
      repaint = "\e[?25l\e[18D\e[1;35m>>> \e[0m\e[36mprint\e[0m\e[0m(\e[0m" \
                "\e[32m'PYDONE'\e[0m\e[0m)\e[0m\e[19D\e[?12l\e[?25h\e[19C"

      expect(repaint).not_to include(echo)
      expect(resolve(waiting(echo: echo, regex: 'PYDONE'), repaint)).to be_nil
      expect(resolve(waiting(echo: echo, regex: 'PYDONE'), "#{repaint}\e[19D\n\e[?2004l\e>PYDONE\n"))
        .to eq({ settled: true, matched: true })
    end

    # bash, captured at 120 columns: readline writes a space and a carriage
    # return where the line wraps, which lands inside the echo. Measured
    # boundary: 110 characters echo as one run, 111 do not.
    it 'ignores an echo that readline split at the wrap' do
      echo = "sleep 3; echo WRAPOK ##{'x' * 89}"
      wrapped = "#{echo[0, 110]} \r#{echo[110..]}"

      expect(resolve(waiting(echo: echo, regex: 'WRAPOK'), wrapped)).to be_nil
      expect(resolve(waiting(echo: echo, regex: 'WRAPOK'), "#{wrapped}\r\nWRAPOK\r\nbash-3.2$ "))
        .to eq({ settled: true, matched: true })
    end

    # A full-screen agent puts the prompt in its transcript and then repaints
    # the whole frame while it thinks, so the input reappears after wherever its
    # first copy ended — which is why the boundary alone cannot be the whole
    # answer, and why the last match is a candidate as well as the next one.
    it 'ignores the input being repainted after the echo has been located' do
      echo = 'handle the BOXDONE case'
      frame = "\e[H\e[2J\e[1;36magent\e[0m\n  \e[35m>\e[0m #{echo}\n\e[90m+------+\e[0m"
      thinking = frame * 12

      expect(resolve(waiting(echo: echo, regex: 'BOXDONE'), thinking)).to be_nil
      expect(resolve(waiting(echo: echo, regex: 'BOXDONE'), "#{thinking}#{frame}\n  reply: BOXDONE\n"))
        .to eq({ settled: true, matched: true })
    end

    # The other half of the same rule: a child that quotes the request back
    # after answering must not push the answer out of reach, which is exactly
    # what taking the *last* copy of the echo as the boundary would do.
    it 'still matches an answer a child follows with a quote of the request' do
      echo = 'summarise the log'

      expect(resolve(waiting(echo: echo, regex: 'QUOTEOK'), "#{echo}\r\nQUOTEOK: finished\r\n(you asked: #{echo})\r\n"))
        .to eq({ settled: true, matched: true })
    end

    # A child with ECHO off puts nothing of the input on the wire at all, so
    # nothing can be located — and refusing to match until something is would
    # hang every send to one of them.
    it 'still matches when the child never echoes anything' do
      expect(resolve(waiting(echo: 'SECRET', regex: 'TERCES'), "answer: TERCES\r\n"))
        .to eq({ settled: true, matched: true })
    end

    # A TUI that reprints scrollback puts an *earlier* sentinel on the wire as
    # ordinary new bytes. Echo#repaint? only covers this send's input, so a
    # reused pattern (DONE \d+) matches the reprint. A unique-per-turn pattern
    # does not — that is the documented workaround, and this example is here so
    # a later "fix" cannot lose it.
    it 'still waits when the reprint is an earlier answer and the pattern is unique to this turn' do
      send = waiting(echo: 'turn two', regex: 'DONE 2')

      expect(resolve(send, "turn two\r\n\e[HDONE 1\r\n")).to be_nil
      expect(resolve(send, "DONE 2\r\n")).to eq({ settled: true, matched: true })
    end

    # An echo a second late is not an echo that never came. Giving up on the
    # search when the grace window closes — rather than merely starting to offer
    # what has arrived — was measured end to end to settle this send 0.8s after
    # the echo landed and a second before the child said anything of its own,
    # handing back a reply consisting entirely of the caller's words.
    it 'still recognises an echo that arrived after the grace window closed' do
      send = waiting(echo: 'please ANSWER now', regex: 'NOTHINGMATCHES', settle_ms: 800)

      send.absorb('', now: 0.8)
      send.absorb("please ANSWER now\n", now: 1.6)

      expect(send.matchable).to eq("\n")
      expect(send.outcome(now: 2.6, child_finished: false, submitted: true, last_output_at: 1.6)).to be_nil

      send.absorb("done\n", now: 3.0)

      # A pattern that has not matched is not answered by quiet — the send runs
      # on to its timeout. That is the rule that makes --wait-for-regex usable
      # at the default settle window; before it, this same shape returned
      # `settled: true, matched: nil` while the child was still working.
      expect(send.outcome(now: 4.0, child_finished: false, submitted: true, last_output_at: 3.0)).to be_nil
      # `matched: false` because this is a regex send: the pattern is reported on
      # the way out however the send ended, so a caller reading it as a tri-state
      # is not told nil for both "no match" and "not a regex send".
      expect(send.outcome(now: 31.0, child_finished: false, submitted: true, last_output_at: 3.0))
        .to eq({ settled: false, timed_out: true, matched: false })
    end

    # The same scenario without a pattern still settles on quiet, which is what
    # keeps the change scoped to the regex path.
    it 'settles on quiet when no pattern was given' do
      send = waiting(echo: 'please ANSWER now', regex: nil, settle_ms: 800)

      send.absorb("please ANSWER now\n", now: 1.6)
      send.absorb("done\n", now: 3.0)

      expect(send.outcome(now: 4.0, child_finished: false, submitted: true, last_output_at: 3.0))
        .to eq({ settled: true })
    end
  end

  # What a `--wait-for-regex` pattern is matched against, and what that bound
  # costs. Matching the whole turn every tick is quadratic in the turn: a 12 MB
  # answer timed out at 90.51s holding 11.46 MB of itself, where the same turn
  # with no pattern settled in 7.38s.
  describe 'how much output a --wait-for-regex pattern is matched against' do
    def waiting(regex)
      Rune::Session::PendingSend.new(client: nil, cursor: 0, echo: 'go', now: 0, settle_ms: 30_000,
                                     timeout_ms: 30_000,
                                     regex: Rune::Session::PendingSend.compile_regex(regex))
    end

    def feed(send, *arrivals, now: 1.0)
      arrivals.each do |text|
        send.absorb(text, now: now)
        outcome = send.outcome(now: now, child_finished: false, submitted: true, last_output_at: now)
        return outcome if outcome
      end
      nil
    end

    def filler(char = 'y') = "#{char * 4095}\n"

    # The scan resumes where the last one stopped, so a marker is matched on the
    # tick it arrives however much the child goes on to print afterwards.
    it 'matches a marker as it arrives rather than waiting for the turn to end' do
      send = waiting('MARKER')

      expect(feed(send, "go\n", *Array.new(3) { filler })).to be_nil
      expect(feed(send, "MARKER\n")).to eq({ settled: true, matched: true })
    end

    # ...and resumes far enough back that a match completed by this read is
    # still seen whole, rather than only from wherever the read began.
    it 'finds a match that straddles several reads' do
      send = waiting('BEGIN[\s\S]*END')

      expect(feed(send, "go\n", *Array.new(30) { filler })).to be_nil
      expect(feed(send, "BEGIN#{'y' * 4090}\n", filler, filler)).to be_nil
      expect(feed(send, "#{'y' * 4092}END\n")).to eq({ settled: true, matched: true })
    end

    # The bound, stated as the thing a caller loses: one match longer than
    # MATCH_SPAN cannot be seen whole by any single scan, so it is never found.
    # Everything shorter always is, whatever the turn grows to.
    it 'does not find a single match longer than the span it re-reads' do
      send = waiting('BEGIN[\s\S]*END')
      chunks = (Rune::Session::PendingSend::MATCH_SPAN / 4096) + 4

      expect(feed(send, "go\n", "BEGIN\n", *Array.new(chunks) { filler })).to be_nil
      expect(feed(send, "END\n")).to be_nil
    end

    # `\A` means the start of the child's answer, not the start of whatever the
    # window happens to hold — which is why the scan is resumed with a position
    # rather than run against a substring. Ruby refuses `\A` at any position
    # past zero, and that is the whole guarantee.
    it 'does not let an anchored pattern match wherever the window now begins' do
      send = waiting('\Ayyy')
      chunks = ((Rune::Session::PendingSend::MATCH_WINDOW_BYTES +
                 Rune::Session::PendingSend::MATCH_WINDOW_SLACK) / 4096) + 20

      expect(feed(send, "go\n", *Array.new(chunks) { filler })).to be_nil
    end

    it 'keeps what it matches against bounded however much the child prints' do
      send = waiting('NEVERMATCHES')

      feed(send, "go\n", *Array.new(400) { filler })

      expect(send.matchable.bytesize)
        .to be <= (Rune::Session::PendingSend::MATCH_WINDOW_BYTES +
                   Rune::Session::PendingSend::MATCH_WINDOW_SLACK)
    end

    # The window is trimmed by bytes on text that is UTF-8 by construction, so
    # the cut has to be moved off a continuation byte — otherwise a sliding
    # window would hand the pattern half a character.
    it 'never cuts a character in half when the window slides' do
      send = waiting('NEVERMATCHES')

      feed(send, "go\n", *Array.new(200) { "#{'⣿' * 1365}\n" })

      expect(send.matchable).to be_valid_encoding
      expect(send.matchable).not_to include('�')
    end
  end

  describe 'what a long-running session costs on disk' do
    # The in-memory window stopped resident memory tracking output, but the
    # transcript file kept every byte for the life of the session and `archive`
    # moves it rather than pruning, so that cost outlived the session paying it:
    # a 150-second run at 500KB/s left 80MB behind permanently.
    def flood(name, chunks:, size: 100_000)
      store.create(name)
      store.write_meta(name, name: name, state: 'running')
      supervisor = Rune::Session::Supervisor.new(name: name, command: ['true'], store: store)
      supervisor.instance_variable_set(:@output_log, store.open_output(name))
      supervisor.instance_variable_set(:@log_bytes, 0)
      written = 0
      chunks.times do
        text = 'z' * size
        # `append` is the real path: it advances the transcript window that
        # rotation's accounting reads from, then logs. Driving `log_event`
        # directly skipped that and made the arithmetic look wrong.
        supervisor.send(:append, text)
        written += text.bytesize
      end
      written
    end

    it 'keeps the transcript file under the ceiling however long the session runs' do
      flood('disk1', chunks: 420)

      expect(File.size(store.output_path('disk1'))).to be < Rune::Session::Store::MAX_LOG_BYTES
    end

    # Rotation must not make cursors lie. What was dropped is recorded, so a
    # cursor still names the same position in the stream.
    it 'accounts for every byte it drops' do
      written = flood('disk2', chunks: 420)

      loaded = Rune::Session::Transcript.load(store.output_path('disk2'))
      expect(loaded.dropped + loaded.text.bytesize).to eq(written)
      expect(loaded.dropped).to be > 0
    end

    it 'resolves a cursor taken after the rotation exactly' do
      flood('disk3', chunks: 420)
      loaded = Rune::Session::Transcript.load(store.output_path('disk3'))

      recent = loaded.cursor - 500

      expect(loaded.from(recent).bytesize).to eq(500)
    end

    it 'returns what it still holds for a cursor from before the rotation' do
      flood('disk4', chunks: 420)
      loaded = Rune::Session::Transcript.load(store.output_path('disk4'))

      expect(loaded.from(1).bytesize).to eq(loaded.text.bytesize)
    end
  end

  # `from` used to compute `since - dropped` against one global accumulator,
  # which is right only while the dropped region is a *prefix* of the stream —
  # true for rotation, and false the moment a failed write records a hole in the
  # middle of a stream that continues afterwards. Every cursor issued before such
  # a hole then resolved |hole| bytes early: already-delivered output, handed back
  # as new, which re-fires prompt detection and every "did my command finish"
  # check built on it.
  describe 'a cursor that spans a hole in the middle of the stream' do
    # A transcript laid out byte by byte, so an example can put a hole exactly
    # where it means to: `[:out, n, marker]` is output the log still holds,
    # `[:gap, n]` bytes the stream lost. Rotation writes one gap, at the head; a
    # write that fails writes one wherever the failure happened.
    def transcript_of(ops)
      path = File.join(@home, "transcript-#{ops.hash.abs}.ndjson")
      File.open(path, 'wb') do |file|
        ops.each do |kind, bytes, marker|
          file.puts(case kind
                    when :out then JSON.generate(event: 'output', ts: 1.0, bytes: bytes,
                                                 text: (marker || 'a') * bytes)
                    when :gap then JSON.generate(event: 'truncated', ts: 1.0, dropped_bytes: bytes)
                    end)
        end
      end
      Rune::Session::Transcript.load(path)
    end

    # The shipped arithmetic, so "unchanged" can be asserted rather than assumed.
    def single_accumulator(loaded, since)
      offset = since - loaded.dropped
      return loaded.text.dup if offset.negative?

      loaded.text.byteslice(offset..) || +''
    end

    # Everything at or after `since` that the log still holds, taken from the
    # layout the example built rather than from anything under test. Bytes before
    # `since` are never part of the answer: the caller already has them.
    def oracle(ops, since)
      abs = 0
      ops.filter_map do |kind, bytes, marker|
        text = (marker || 'a') * bytes
        start = abs
        abs += bytes
        next if kind != :out || start + bytes <= since

        since <= start ? text : text.byteslice(since - start, bytes)
      end.join
    end

    def probe_points(ops)
      abs = 0
      ops.flat_map do |_kind, bytes, _marker|
        start = abs
        abs += bytes
        [start, start + 1, start + (bytes / 2), start + bytes - 1]
      end.push(abs, abs - 1, 0).reject(&:negative?).uniq.sort
    end

    it 'answers exactly as it always did when nothing was ever dropped' do
      ops = [[:out, 4_000, 'a'], [:out, 4_000, 'b'], [:out, 4_000, 'c']]
      loaded = transcript_of(ops)

      expect(loaded.gaps).to eq([])
      expect(loaded.cursor).to eq(12_000)
      probe_points(ops).each do |since|
        expect(loaded.from(since)).to eq(single_accumulator(loaded, since)), "at since=#{since}"
      end
    end

    it 'answers exactly as it always did when a rotation dropped a prefix' do
      ops = [[:gap, 48_000], [:out, 4_000, 'a'], [:out, 4_000, 'b']]
      loaded = transcript_of(ops)

      expect(loaded.gaps).to eq([[0, 48_000]])
      expect(loaded.cursor).to eq(56_000)
      probe_points(ops).each do |since|
        expect(loaded.from(since)).to eq(single_accumulator(loaded, since)), "at since=#{since}"
      end
    end

    # The reproduction: 25 chunks, a 48_000-byte hole, 25 more. A cursor from
    # before the hole resolved 48_000 bytes early and replayed the whole first
    # half of the stream.
    it 'does not replay output it has already delivered before the hole' do
      loaded = transcript_of((1..25).map { [:out, 4_000, 'a'] } + [[:gap, 48_000]] +
                             (1..25).map { [:out, 4_000, 'b'] })

      expect(loaded.cursor).to eq(248_000)
      expect(loaded.dropped).to eq(48_000)
      expect(loaded.from(100_000).bytesize).to eq(100_000)
      expect(loaded.from(100_000)[0, 4]).to eq('bbbb')
      expect(loaded.from(148_000).bytesize).to eq(100_000)
      expect(loaded.from(228_000).bytesize).to eq(20_000)
    end

    # Those bytes are gone whichever way the cursor is bent, so it is bent
    # forward: later output is honest where earlier output is not.
    it 'clamps a cursor that lands inside the hole forward to its end' do
      loaded = transcript_of((1..25).map { [:out, 4_000, 'a'] } + [[:gap, 48_000]] +
                             (1..25).map { [:out, 4_000, 'b'] })

      expect(loaded.from(124_000)).to eq(loaded.from(148_000))
      expect(loaded.from(124_000)[0, 4]).to eq('bbbb')
    end

    it 'resolves a cursor before, inside and after each of several holes' do
      ops = [[:out, 4_000, 'a'], [:gap, 12_000], [:out, 4_000, 'b'], [:gap, 8_000],
             [:out, 4_000, 'c'], [:gap, 100_000], [:out, 4_000, 'd']]
      loaded = transcript_of(ops)

      expect(loaded.gaps).to eq([[4_000, 12_000], [8_000, 20_000], [12_000, 120_000]])
      probe_points(ops).each do |since|
        expect(loaded.from(since)).to eq(oracle(ops, since)), "at since=#{since}"
      end
    end

    # A rotation drops a prefix that may already contain a hole, and the head
    # event it writes covers both — so the whole thing collapses back to the one
    # shape the old arithmetic could describe.
    it 'collapses to a single prefix when a rotation drops a region holding a hole' do
      ops = [[:gap, 60_000], [:out, 4_000, 'a'], [:out, 4_000, 'b']]
      loaded = transcript_of(ops)

      expect(loaded.gaps).to eq([[0, 60_000]])
      probe_points(ops).each do |since|
        expect(loaded.from(since)).to eq(single_accumulator(loaded, since)), "at since=#{since}"
      end
    end

    # And a rotation whose *kept* tail still holds one leaves two, in order.
    it 'keeps a hole that survived inside the tail a rotation kept' do
      ops = [[:gap, 60_000], [:out, 4_000, 'a'], [:gap, 9_000], [:out, 4_000, 'b']]
      loaded = transcript_of(ops)

      expect(loaded.gaps).to eq([[0, 60_000], [4_000, 69_000]])
      expect(loaded.cursor).to eq(77_000)
      probe_points(ops).each do |since|
        expect(loaded.from(since)).to eq(oracle(ops, since)), "at since=#{since}"
      end
    end
  end

  # `--since` is a raw byte offset. A caller doing arithmetic on one
  # (`--since=$((cursor-200))`) can land inside a multi-byte character.
  # `.scrub` then replaced each orphaned continuation with U+FFFD under
  # `status: ok`, so a consumer could not tell rune's slicing from a
  # replacement the child actually emitted. Measured on `こY` (E3 81 93 59):
  # `--since=1` returned two U+FFFD then `Y`; `--since=2` returned one.
  # Cursors rune itself issues never land here — `UTF8StreamDecoder` holds a
  # trailing incomplete sequence — so this is only the caller-arithmetic case.
  describe 'a --since offset that lands inside a multi-byte character' do
    # こ is U+3053, bytes E3 81 93. Offsets 1 and 2 are continuation bytes.
    let(:text) { 'こY' }
    let(:loaded) { Rune::Session::Transcript.new(text, 0) }

    it 'snaps forward to the next character start rather than inventing U+FFFD' do
      expect(loaded.from(0)).to eq('こY')
      expect(loaded.from(1)).to eq('Y')
      expect(loaded.from(2)).to eq('Y')
      expect(loaded.from(3)).to eq('Y')
      expect(loaded.from(4)).to eq('')
    end

    it 'never returns a replacement character the child did not emit' do
      (0..text.bytesize).each do |since|
        slice = loaded.from(since)
        expect(slice).to be_valid_encoding
        expect(slice).not_to include("\uFFFD")
      end
    end

    it 'snaps a 4-byte emoji the same way' do
      loaded = Rune::Session::Transcript.new('X😀Y', 0)

      expect(loaded.from(0)).to eq('X😀Y')
      expect(loaded.from(1)).to eq('😀Y')
      2.upto(4) { |since| expect(loaded.from(since)).to eq('Y') }
      expect(loaded.from(5)).to eq('Y')
      expect(loaded.from(6)).to eq('')
    end
  end

  # A transcript write that fails is *recorded*, not merely survived. The
  # in-memory cursor has already advanced — those bytes really were produced —
  # so a hole nothing accounts for makes every cursor `send` hands out
  # unresolvable by `read`, permanently and without a word: reproduced on a full
  # filesystem, where `send` answered `cursor: 1849946` while `read` reported
  # 187221 with no `dropped_bytes`, and `read --since=1849946` returned "" for
  # the rest of the session's life.
  describe 'a transcript write that fails' do
    # A handle that can be told to fail, and to fail *part-way*, which is what a
    # filesystem running out of room actually does: it writes what fits and then
    # raises, leaving a fragment at the end of the file.
    def tearing_log(file)
      log = Object.new
      log.instance_variable_set(:@file, file)
      log.instance_variable_set(:@mode, :ok)
      log.instance_variable_set(:@tear, 0)
      log.define_singleton_method(:closed?) { @file.closed? }
      log.define_singleton_method(:close) { @file.close }
      log.define_singleton_method(:mode=) { |value| @mode = value }
      log.define_singleton_method(:tear=) { |value| @tear = value }
      log.define_singleton_method(:write) do |payload|
        case @mode
        when :ok then @file.write(payload)
        when :dead then raise Errno::ENOSPC
        else
          # A write(2) that transferred every byte returns the full count and
          # does not error, so only a strictly short transfer raises.
          next @file.write(payload) if @tear >= payload.bytesize

          @file.write(payload.byteslice(0, @tear)) if @tear.positive?
          raise Errno::ENOSPC
        end
      end
      log
    end

    def breakable_session(name)
      disk = store
      disk.create(name)
      disk.write_meta(name, name: name, state: 'running')
      log = tearing_log(disk.open_output(name))
      supervisor = Rune::Session::Supervisor.new(name: name, command: ['true'], store: disk)
      supervisor.instance_variable_set(:@output_log, log)
      supervisor.instance_variable_set(:@log_bytes, 0)
      [supervisor, log]
    end

    # `append` is the real path: it advances the transcript window rotation's
    # accounting reads from, then logs.
    def emit(supervisor, chunks) = chunks.times { supervisor.send(:append, 'z' * chunk_bytes) }

    def cursor_of(supervisor) = supervisor.send(:transcript_bytes)

    def chunk_bytes = 3_000

    def small_log_bounds
      stub_const('Rune::Session::Store::MAX_LOG_BYTES', 300_000)
      stub_const('Rune::Session::Store::LOG_KEEP_BYTES', 250_000)
    end

    it 'carries what it could not write and records it as soon as writing resumes' do
      supervisor, log = breakable_session('gap1')
      emit(supervisor, 2)
      log.mode = :dead
      emit(supervisor, 4)
      log.mode = :ok
      emit(supervisor, 1)

      loaded = Rune::Session::Transcript.load(store.output_path('gap1'))

      expect(loaded.dropped).to eq(4 * chunk_bytes)
      expect(loaded.cursor).to eq(cursor_of(supervisor))
      expect(loaded.from(cursor_of(supervisor) - 1_000).bytesize).to eq(1_000)
    end

    # The hole is in the *middle* — output was recorded before it and after it —
    # which is the shape rotation never produced and `from` was never taught.
    it 'leaves a cursor from before the hole resolving to what followed it, not to the whole log' do
      supervisor, log = breakable_session('gap3')
      emit(supervisor, 2)
      log.mode = :dead
      emit(supervisor, 4)
      log.mode = :ok
      emit(supervisor, 3)

      loaded = Rune::Session::Transcript.load(store.output_path('gap3'))

      expect(loaded.gaps).to eq([[2 * chunk_bytes, 4 * chunk_bytes]])
      # A cursor taken after the first two chunks: everything since is one chunk
      # of recorded output before the hole plus three after it — never the four
      # in between, which nothing holds.
      expect(loaded.from(chunk_bytes).bytesize).to eq(4 * chunk_bytes)
      expect(loaded.from(cursor_of(supervisor) - 1).bytesize).to eq(1)
    end

    # Until a write succeeds there is nowhere on disk to record the hole, so the
    # supervisor's own memory is the only place the skew is known at all.
    it 'reports the skew while there is still nowhere to record it' do
      supervisor, log = breakable_session('gap2')
      emit(supervisor, 2)
      log.mode = :dead
      emit(supervisor, 3)

      expect(supervisor.send(:status_payload)[:transcript_gap_bytes]).to eq(3 * chunk_bytes)

      log.mode = :ok
      emit(supervisor, 1)

      expect(supervisor.send(:status_payload)).not_to have_key(:transcript_gap_bytes)
    end

    # The hazard the torn marker exists for: a partial write can leave a
    # *complete* JSON record that merely never got its newline, which a later
    # append would silently terminate — counting the gap a second time. Swept
    # across every split point of the record that carries it.
    it 'never counts a gap twice, wherever the write recording it is torn' do
      deltas = (0..90).map do |tear|
        name = "torn#{tear}"
        supervisor, log = breakable_session(name)
        emit(supervisor, 2)
        log.mode = :dead
        emit(supervisor, 2)
        log.mode = :torn
        log.tear = tear
        emit(supervisor, 1)
        log.mode = :ok
        emit(supervisor, 2)
        Rune::Session::Transcript.load(store.output_path(name)).cursor - cursor_of(supervisor)
      end

      expect(deltas.uniq).to eq([0])
    end

    # A rotation keeps a tail, and a hole recorded mid-stream can land inside it.
    # Counting only `output` there put every later cursor past the end of the
    # stream: measured as a 400_000-byte overshoot, with `from(cursor - 1234)`
    # returning 401_234 bytes.
    it 'does not count a mid-stream hole twice when a rotation keeps it' do
      small_log_bounds
      supervisor, log = breakable_session('rot2')
      emit(supervisor, 60)
      log.mode = :dead
      emit(supervisor, 4)
      log.mode = :ok
      emit(supervisor, 41)

      loaded = Rune::Session::Transcript.load(store.output_path('rot2'))

      expect(loaded.dropped).to be > 4 * chunk_bytes
      expect(loaded.gaps.length).to eq(2)
      expect(loaded.cursor).to eq(cursor_of(supervisor))
      expect(loaded.from(cursor_of(supervisor) - 1_234).bytesize).to eq(1_234)
    end

    # The fragment an *output* write leaves is the dangerous one, because it
    # still reads as an output record to the rotation scanner: it carries
    # `"event":"output"` and `"bytes":N` while `Transcript.load` cannot parse it
    # and skips it. Counting it credits the kept region with output no reader
    # will see, and the head event a rotation writes is `total_output - kept`, so
    # every later cursor sits N low — permanently, with no `truncated` event and
    # no warning. Worse than doing nothing at all, because the torn marker
    # terminates each fragment into a countable line of its own: measured on a
    # 12MB transcript with 1/4/10 torn writes buried in the kept tail,
    # -4096/-16384/-40960 bytes of skew, against a flat -4096 without the marker.
    it 'does not count the fragment a torn output write leaves, wherever it is torn' do
      small_log_bounds
      deltas = [0, 20, 44, 48, 60, 120, 900, 2_500].to_h do |tear|
        name = "outputtorn#{tear}"
        supervisor, log = breakable_session(name)
        emit(supervisor, 60)
        log.mode = :torn
        log.tear = tear
        emit(supervisor, 1)
        log.mode = :ok
        emit(supervisor, 45)
        loaded = Rune::Session::Transcript.load(store.output_path(name))
        # A rotation has to have happened, or the assertion is vacuous.
        expect(loaded.dropped).to be_positive
        [tear, loaded.cursor - cursor_of(supervisor)]
      end

      expect(deltas.reject { |_tear, delta| delta.zero? }).to eq({})
    end

    # The other face. The whole-record guard must not start dropping the records
    # a healthy transcript is made of, which would push cursors the other way.
    it 'still accounts for every byte of a transcript with no torn write in it' do
      small_log_bounds
      supervisor, = breakable_session('healthy')
      emit(supervisor, 110)

      loaded = Rune::Session::Transcript.load(store.output_path('healthy'))

      expect(loaded.dropped).to be_positive
      expect(loaded.cursor).to eq(cursor_of(supervisor))
      expect(loaded.from(cursor_of(supervisor) - 1_234).bytesize).to eq(1_234)
    end

    # `output_bytes_from` decides on a line's last byte rather than by parsing
    # it, because parsing every line of the kept region cost 96MB per rotation.
    # That is only sound if it accepts exactly what `Transcript.load` parses, so
    # the two are swept against each other over every split point of every shape
    # the supervisor writes — with braces, quotes, escapes and the marker's own
    # bytes inside the payload, which is where a byte test can be fooled.
    #
    # Two shapes, because those are the two a transcript can hold: a fragment a
    # live supervisor left, which its next write terminated with `TORN_MARKER`,
    # and a fragment the file simply ends on because the supervisor was killed
    # mid-write. The second is the one the byte test cannot decide — a cut inside
    # a `text` field holding a `}` ends on `}` without being a record — which is
    # why a line with no trailing newline is parsed outright.
    it 'counts exactly the lines the transcript reader parses' do
      texts = ['x' * 8, '}}}}', 'a}b{c}d', '|torn|torn', 'brace }', '{"event":"output","bytes":9}',
               "\e[1;31mred\e[0m}", '"quoted}"']
      records = texts.flat_map do |text|
        [JSON.generate(event: 'output', ts: 1.5, bytes: text.bytesize, text: text),
         JSON.generate(event: 'truncated', ts: 1.5, dropped_bytes: text.bytesize)]
      end
      parses = lambda do |line|
        !JSON.parse(line).nil?
      rescue JSON::ParserError
        false
      end

      lines = records.flat_map do |record|
        (0..record.bytesize).flat_map do |split|
          fragment = record.byteslice(0, split)
          ["#{fragment}#{Rune::Session::Supervisor::TORN_MARKER}", fragment].reject(&:empty?)
        end
      end
      disagreements = lines.reject { |line| store.whole_record?(line) == parses.call(line) }

      expect(disagreements).to eq([])
      expect(records).to all(satisfy { |record| store.whole_record?("#{record}\n") })
    end
  end

  describe 'telling working from finished' do
    # A caller was grepping the callee's own rendered UI for a busy marker,
    # which is presentation rather than API and changes without notice.
    def printing_child
      ['ruby', '-e', <<~CHILD]
        STDOUT.sync = true
        while (line = STDIN.gets)
          12.times { print("working\r\n"); sleep 0.12 }
          print("DONE\r\n")
        end
      CHILD
    end

    it 'reports the child as busy while it is printing, and idle once it stops' do
      start_session('busy1', printing_child)
      session('send', '--name=busy1', '--no-wait', '--', 'go')
      wait_until(reason: 'output to start') { session('read', '--name=busy1').data[:output].include?('working') }

      expect(session('read', '--name=busy1').data[:child_busy]).to be true

      wait_until(reason: 'the child to finish') { session('read', '--name=busy1').data[:output].include?('DONE') }
      sleep 1.2
      expect(session('read', '--name=busy1').data[:child_busy]).to be false
    end
  end

  describe 'searching a transcript' do
    # `--since` and `--tail` do not help when what you want is in the middle. A
    # day's work with a driven agent reached 379KB, and pulling it into a
    # caller's context to find one line is what this avoids.
    def chatty_child
      ['ruby', '-e', <<~CHILD]
        STDOUT.sync = true
        while (line = STDIN.gets)
          puts 'before-' + line.strip
          puts 'THE BOARD: alpha beta'
          puts 'after-' + line.strip
        end
      CHILD
    end

    def seeded(name, turns: 2)
      start_session(name, chatty_child)
      turns.times { |i| session('send', "--name=#{name}", '--settle-ms=300', '--timeout-ms=15000', '--', "t#{i}") }
    end

    it 'keeps only matching lines and counts them' do
      seeded('gr1')

      result = session('read', '--name=gr1', '--grep=THE BOARD')

      expect(result.data[:grep_matches]).to eq(2)
      expect(result.data[:output].lines.map(&:strip).uniq).to eq(['THE BOARD: alpha beta'])
    end

    it 'includes surrounding lines with --context' do
      seeded('gr2', turns: 1)

      result = session('read', '--name=gr2', '--grep=THE BOARD', '--context=1')

      expect(result.data[:output]).to include('before-t0')
      expect(result.data[:output]).to include('after-t0')
    end

    # A full-screen agent's repaint frames split words across escape sequences,
    # so matching the raw stream would miss patterns that are plainly on screen.
    it 'matches the cleaned text rather than the repaint stream' do
      painter = 'STDOUT.sync = true; print("\e[1mFOUND\e[0m-IT\r\n")'
      start_session('gr3', ['ruby', '-e', painter])
      wait_until(reason: 'output') { session('read', '--name=gr3').data[:output].include?('IT') }

      expect(session('read', '--name=gr3', '--grep=FOUND-IT').data[:grep_matches]).to eq(1)
    end

    it 'reports an unparseable pattern instead of raising' do
      seeded('gr4', turns: 1)

      result = session('read', '--name=gr4', '--grep=(')

      expect(result).to be_success
      expect(result.data[:grep_error]).to include('invalid --grep pattern')
    end

    # It used to return the whole transcript under `status: ok` — the exact
    # opposite of what the same read does for a valid pattern that matches
    # nothing. A caller that did not read `grep_error` saw every line as though
    # it had matched, at the maximum possible cost.
    it 'returns no output at all for a pattern that will not compile' do
      seeded('gr5', turns: 1)

      broken = session('read', '--name=gr5', '--grep=[unclosed')
      unmatched = session('read', '--name=gr5', '--grep=NOTHING-MATCHES-THIS')

      expect(broken.data[:output]).to eq('')
      expect(broken.data[:clean_output]).to eq('')
      expect(broken.data[:output]).to eq(unmatched.data[:output])
    end

    # `grep_matches: 0` would claim a search happened. Absent says it did not.
    it 'omits grep_matches when the pattern never compiled, and says why' do
      seeded('gr6', turns: 1)

      result = session('read', '--name=gr6', '--grep=[unclosed')

      expect(result.data).not_to have_key(:grep_matches)
      expect(result.data[:grep]).to eq('[unclosed')
      expect(result.data[:grep_error]).to include('premature end of char-class')
      expect(result.data[:grep_error]).to include('returned no output')
    end

    # The read still succeeds, which is the whole reason grep_error exists: the
    # cursor and the liveness fields have nothing to do with the pattern, and a
    # failure would take them down with it.
    it 'still reports the cursor and liveness fields when the pattern is broken' do
      seeded('gr7', turns: 1)

      result = session('read', '--name=gr7', '--grep=[unclosed')

      expect(result).to be_success
      expect(result.data[:cursor]).to be > 0
      expect(result.data).to have_key(:child_busy)
    end

    # In a terminal the reply renders as its text, which is now empty. A blank
    # line with no reason for it would be a worse answer than the transcript
    # this used to print.
    it 'shows the reason in human mode, where the text alone would be a blank line' do
      rendered = StringIO.new
      Rune::Commands::SessionCommand.new.human_render(
        { action: 'read', clean_output: '',
          grep_error: 'invalid --grep pattern: premature end of char-class' }, rendered
      )

      expect(rendered.string).to include('invalid --grep pattern')
    end
  end

  # `rune session frobnicate` has always been rejected; a mistyped *flag* was
  # not. `send --name=x --settle_ms 500 'echo HELLO'` joined the flag, its value
  # and the input with spaces and typed the lot at the child, answering
  # `status: ok`.
  describe 'a mistyped flag before the first operand' do
    def parsed(*argv, operand_owns_flags: false)
      Rune::Commands::SessionCommand.new
                                    .send(:extract_options, argv, operand_owns_flags: operand_owns_flags)
    end

    it 'refuses the underscored spelling and names the flag that was meant' do
      _options, _rest, message = parsed('--name=x', '--settle_ms', '500', 'echo HELLO')

      expect(message).to include('Unknown option: --settle_ms')
      expect(message).to include('Did you mean --settle-ms?')
    end

    it 'refuses a flag it has no suggestion for, and says how to send it as input' do
      _options, _rest, message = parsed('--name=x', '--frobnicate', 'hi')

      expect(message).to include('Unknown option: --frobnicate')
      expect(message).not_to include('Did you mean')
      expect(message).to include('-- --frobnicate')
    end

    it 'still passes a flag-shaped token through untouched after a separator' do
      _options, rest, message = parsed('--name=x', '--', '--settle_ms')

      expect(message).to be_nil
      expect(rest).to eq(['--', '--settle_ms'])
    end

    it 'does not mistake --- section --- for a flag, quoted or not' do
      _options, rest, message = parsed('--name=x', '---', 'section', '---')
      _options2, _rest2, quoted = parsed('--name=x', '--- section ---')

      expect(message).to be_nil
      expect(quoted).to be_nil
      expect(rest).to eq(['---', 'section', '---'])
    end

    # The rule is per-subcommand, because the operand means different things.
    #
    # `start`'s operand is a program followed by that program's own argv, so a
    # flag after it belongs to the child: `start --name=x claude --resume` and
    # `start --name=x claude --dangerously-skip-permissions` must keep working.
    it 'leaves flag-shaped tokens after the program name alone, for start' do
      _options, rest, message = parsed('--name=x', 'claude', '--resume', operand_owns_flags: true)

      expect(message).to be_nil
      expect(rest).to eq(%w[claude --resume])
    end

    # `send`'s operand is literal text, and rune *consumes* a correctly-spelled
    # flag after it — `send 'echo hi' --settle-ms 600` really does have its flag
    # eaten. So a mistyped one there has to be an error rather than input, or
    # the parser permutes for consumption and not for validation.
    it 'rejects a mistyped flag after the operand, for everything else' do
      _options, _rest, message = parsed('--name=x', 'echo hi', '--settle_ms', '600')

      expect(message).to include('--settle_ms')
      expect(message).to include('--settle-ms')
    end

    it 'still passes anything after a -- separator through untouched' do
      _options, rest, message = parsed('--name=x', '--', 'git', 'log', '--oneline')

      expect(message).to be_nil
      expect(rest).to eq(%w[-- git log --oneline])
    end
  end

  describe 'how an attachment reports the way it ended' do
    # Reported from real use against a grok session: rune printed both
    # "detached; the session is still running" and "Session ended while
    # attached" in the same exit, and exited 1. One of those is always wrong.
    # The note fired whenever an attachment had been established, rather than
    # only when the human actually detached.
    def attachment_after(pump_result)
      announce = StringIO.new
      attachment = Rune::Session::Attachment.new('/nonexistent.sock', announce: announce)
      attachment.instance_variable_set(:@attached, true)
      attachment.instance_variable_set(:@detached, pump_result)
      attachment.send(:close_quietly, nil)
      announce.string
    end

    it 'says the session is still running only when the human detached' do
      expect(attachment_after(true)).to include('still running')
    end

    it 'says nothing about the session still running when it ended underneath' do
      expect(attachment_after(false)).not_to include('still running')
    end

    # The attachment can tell that output stopped; it cannot tell a child that
    # exited from a supervisor that was stopped, so it points at the command
    # that can rather than asserting a cause.
    it 'reports what it knows and where to look' do
      expect(Rune::Session::Attachment::ENDED_WHILE_ATTACHED).to include('rune session list')
      expect(Rune::Session::Attachment::ENDED_WHILE_ATTACHED).not_to include('supervisor exited')
    end
  end

  describe 'what a long-running session costs' do
    let(:supervisor) do
      Rune::Session::Supervisor.new(name: 'unit', command: ['true'], store: store)
    end

    def backlog = Rune::Session::Supervisor::ATTACH_BACKLOG_BYTES

    # A persistent session is the entire feature, so what the supervisor holds
    # while one runs is not a detail. Measured before this bound existed:
    # resident memory tracked output one-for-one — 27MB to 69MB in eighty
    # seconds at 500KB/s — and never came down.
    it 'holds a bounded window rather than every byte the child ever produced' do
      12.times { supervisor.send(:append, 'x' * backlog) }

      held = supervisor.instance_variable_get(:@transcript).bytesize
      expect(held).to be <= (backlog * 2)
      # ...while the cursor still counts everything, because clients read the
      # full transcript from the log file, not from this process.
      expect(supervisor.send(:transcript_bytes)).to eq(backlog * 12)
    end

    # Trimming must never outrun a send that is still waiting, however long its
    # turn runs or however much the child prints during it.
    it 'keeps everything an in-flight send has produced, past the backlog bound' do
      supervisor.send(:append, 'earlier output')
      cursor = supervisor.send(:transcript_bytes)
      supervisor.instance_variable_set(
        :@pending,
        Rune::Session::PendingSend.new(client: nil, cursor: cursor, echo: '', now: 0,
                                       settle_ms: 800, timeout_ms: 15_000)
      )
      6.times { supervisor.send(:append, 'y' * backlog) }

      expect(supervisor.send(:slice_from, cursor).bytesize).to eq(backlog * 6)
    end

    it 'still replays only the backlog to an attaching terminal' do
      4.times { supervisor.send(:append, 'z' * backlog) }

      expect(supervisor.send(:recent_transcript).bytesize).to eq(backlog)
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

    # Backpressure would otherwise defeat the delay entirely: `drain_outbox` and
    # `deliver_submit` run in the same tick, so a deadline already in the past
    # fires microseconds after the text tail drains and lands in the child's
    # same read. The deadline has to be measured from the last text byte going
    # out, not from when the send arrived. Found by having claude review this
    # path through rune.
    it 'restarts the terminator delay while the text is still queued' do
      supervisor = Rune::Session::Supervisor.new(name: 'unit', command: ['true'], store: store)
      reader, writer = IO.pipe
      supervisor.instance_variable_set(:@writer, writer)
      supervisor.instance_variable_get(:@outbox)[writer] << 'not yet drained'
      # Already due, and would fire the instant the queue empties.
      supervisor.instance_variable_set(:@submit_at, supervisor.send(:monotonic) - 1)

      supervisor.send(:deliver_submit)

      expect(supervisor.instance_variable_get(:@submit_at)).to be > supervisor.send(:monotonic)
      expect(supervisor.instance_variable_get(:@outbox)[writer]).to eq('not yet drained')
      [reader, writer].each { |io| io.close unless io.closed? }
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

  # `attach` resizes the child to whatever terminal took it over, so a fixed
  # 40x120 render is wrong for the whole time a human is attached from a window
  # of any other shape. Measured end to end against two independent emulators
  # before this: all 40 rendered rows differed from what a real 30x100 attach
  # was showing; after, none did.
  describe 'the screen renders at the size the child is actually running at' do
    # Lays its output out against the pty three ways at once — how many lines it
    # emits (so a shorter terminal scrolls and a taller one does not), how wide
    # each line is (so a narrower terminal wraps it), and what it prints — and
    # repaints all of it on SIGWINCH, as every full-screen agent CLI does.
    def size_painting_child
      script = <<~CHILD
        require 'io/console'
        STDOUT.sync = true
        def paint
          rows, cols = STDOUT.winsize
          print "\\e[H\\e[2J"
          (1..(rows + 3)).each { |line| print format('N%02d', line) + "\\n" }
          print('x' * (cols + 5))
          print "\\nsize \#{rows}x\#{cols}\\n"
        end
        Signal.trap('WINCH') { paint }
        paint
        sleep
      CHILD
      ['ruby', '-e', script]
    end

    # Exactly the frame `Attachment#forward_resize` sends, over its own
    # short-lived control connection.
    def resize(name, rows, cols)
      Rune::Session::Client.new(store.socket_path(name)).request({ op: 'resize', rows: rows, cols: cols })
    end

    def wait_for_repaint(name, marker)
      wait_until(reason: "a repaint at #{marker}") do
        session('read', "--name=#{name}", '--screen').data[:screen].to_s.include?(marker)
      end
    end

    it 'follows the child to a new terminal size instead of rendering at the default' do
      start_session('win1', size_painting_child)
      wait_for_repaint('win1', 'size 40x120')
      resize('win1', 24, 80)
      wait_for_repaint('win1', 'size 24x80')

      screen = session('read', '--name=win1', '--screen').data[:screen]

      # Rows: 27 lines fit in a 40-row grid, so the old render kept N01. A real
      # 24-row terminal scrolled it away.
      expect(screen).not_to include('N01')
      expect(screen).to include('N27')
      # Columns: 85 characters is one line at 120 columns and two at 80.
      expect(screen.lines.map(&:chomp)).to include('x' * 80, 'x' * 5)
    end

    it 'reports the size it rendered at, so a caller can tell a real geometry from the fallback' do
      start_session('win2', size_painting_child)
      wait_for_repaint('win2', 'size 40x120')
      resize('win2', 30, 100)
      wait_for_repaint('win2', 'size 30x100')

      result = session('read', '--name=win2', '--screen')

      expect(result.data[:screen_rows]).to eq(30)
      expect(result.data[:screen_cols]).to eq(100)
      expect(store.read_meta('win2')).to include(rows: 30, cols: 100)
    end

    it 'renders send --screen at the same size as read --screen' do
      start_session('win3', ['bash', '--norc', '-i'])
      resize('win3', 12, 40)
      wait_until(reason: 'the resize to be recorded') { store.read_meta('win3')[:rows] == 12 }

      result = session('send', '--name=win3', '--screen', '--settle-ms=400', '--timeout-ms=15000',
                       '--', 'printf "y%.0s" $(seq 1 45); echo')

      expect(result.data[:screen_rows]).to eq(12)
      expect(result.data[:screen_cols]).to eq(40)
      expect(result.data[:screen].lines.map(&:chomp)).to include('y' * 40)
    end

    # A session directory written before the size was recorded, which is every
    # session that predates this. The fallback is the previous behaviour, so
    # such a transcript renders exactly as it always did rather than failing.
    it 'falls back to the documented default when no size was ever recorded' do
      start_session('win4', size_painting_child)
      wait_for_repaint('win4', 'size 40x120')
      session('stop', '--name=win4')
      store.write_meta('win4', store.read_meta('win4').except(:rows, :cols))

      result = session('read', '--name=win4', '--screen')

      expect(result.data[:screen_rows]).to eq(Rune::Parsers::ScreenRenderer::DEFAULT_ROWS)
      expect(result.data[:screen_cols]).to eq(Rune::Parsers::ScreenRenderer::DEFAULT_COLUMNS)
      expect(result.data[:screen]).to include('size 40x120')
    end

    # meta.json is a file on disk. A hand-edited or truncated one must not be
    # able to turn `read --screen` into a crash or an arbitrary allocation.
    it 'ignores a recorded size that is not a usable terminal' do
      start_session('win5', size_painting_child)
      wait_for_repaint('win5', 'size 40x120')
      session('stop', '--name=win5')
      store.update_meta('win5', rows: 10**12, cols: 'wide')

      result = session('read', '--name=win5', '--screen')

      expect(result).to be_success
      expect(result.data[:screen_rows]).to eq(Rune::Parsers::ScreenRenderer::MAX_ROWS)
      expect(result.data[:screen_cols]).to eq(Rune::Parsers::ScreenRenderer::DEFAULT_COLUMNS)
      expect(result.data[:screen_size_recorded]).to be(false)
    end

    # The size pair alone cannot answer this: a session attached from a 40-row
    # terminal records exactly the fallback numbers. Nothing distinguished the
    # two until `screen_size_recorded`, so the docs could not honestly claim a
    # caller was able to tell.
    it 'distinguishes a recorded 40x120 from the 40x120 default' do
      start_session('win6', size_painting_child)
      wait_for_repaint('win6', 'size 40x120')
      before = session('read', '--name=win6', '--screen').data

      resize('win6', Rune::Parsers::ScreenRenderer::DEFAULT_ROWS, Rune::Parsers::ScreenRenderer::DEFAULT_COLUMNS)
      wait_until(reason: 'the resize to be recorded') { store.read_meta('win6')[:rows] == 40 }
      after = session('read', '--name=win6', '--screen').data

      expect(before.values_at(:screen_rows, :screen_cols)).to eq(after.values_at(:screen_rows, :screen_cols))
      expect(before[:screen_size_recorded]).to be(false)
      expect(after[:screen_size_recorded]).to be(true)
    end

    # The supervisor sets the pty to the default and deliberately does not
    # record it: recording would write meta a second time during launch, against
    # the parent's own update, and an absent size already renders at exactly
    # those dimensions.
    it 'records nothing until the child is actually resized' do
      start_session('win7', size_painting_child)
      wait_for_repaint('win7', 'size 40x120')

      expect(store.read_meta('win7')).not_to include(:rows, :cols)
      expect(session('read', '--name=win7', '--screen').data[:screen]).to include('size 40x120')
    end

    # A pty's winsize fields are 16-bit, so the control socket can be handed
    # 65535x65535 and the kernel will take it. Rendering is what pays: the
    # recorded size drives an eagerly allocated grid on every later `--screen`,
    # for the rest of the session's life, which is the denial of service
    # CHG-0056 clamped one layer down.
    it 'clamps an absurd resize where it is recorded, not where it is rendered' do
      start_session('win8', size_painting_child)
      wait_for_repaint('win8', 'size 40x120')
      resize('win8', 65_535, 65_535)
      # The CHILD gets what it asked for. Clamping the pty as well silently
      # handed a 400-row terminal's child 300 rows, so a TUI painted its top 300
      # forever with nothing in the ack saying so. The ceiling protects rune's
      # renderer, which is rune's problem and not the child's.
      wait_for_repaint('win8', 'size 65535x65535')

      result = session('read', '--name=win8', '--screen')

      expect(store.read_meta('win8')).to include(rows: Rune::Session::Supervisor::MAX_ROWS,
                                                 cols: Rune::Session::Supervisor::MAX_COLUMNS)
      expect(result.data.values_at(:screen_rows, :screen_cols))
        .to eq([Rune::Session::Supervisor::MAX_ROWS, Rune::Session::Supervisor::MAX_COLUMNS])
      # A size rune had to reduce is not the child's geometry, so it is not
      # "recorded" either — which is what the spec promised before the code did.
      expect(result.data[:screen_size_recorded]).to be false
    end
  end

  # Recording the winsize turned meta.json from a file written a handful of
  # times per session into one written per resize, and a human dragging a window
  # edge emits a SIGWINCH per frame. Every other rune process answers "does this
  # session exist, and is it alive?" out of this file.
  describe 'meta.json is replaced, never truncated in place' do
    it 'swaps a new file in rather than emptying the one readers are holding' do
      store.create('meta1')
      store.write_meta('meta1', name: 'meta1', state: 'running')
      before = File.stat(store.meta_path('meta1')).ino

      store.write_meta('meta1', name: 'meta1', state: 'running', rows: 30, cols: 100)

      # A different inode is the observable difference between `rename` and
      # O_TRUNC: truncating keeps the file a concurrent reader already opened
      # and empties it under them, which is exactly the window where `send`
      # answered "No such session".
      expect(File.stat(store.meta_path('meta1')).ino).not_to eq(before)
      expect(store.read_meta('meta1')).to include(rows: 30, cols: 100)
    end

    it 'leaves the replacement owner-only and drops its temp file' do
      store.create('meta2')
      store.write_meta('meta2', name: 'meta2', state: 'running')

      expect(File.stat(store.meta_path('meta2')).mode & 0o777).to eq(Rune::Session::Store::FILE_MODE)
      expect(Dir.children(store.session_dir('meta2')).grep(/writing/)).to be_empty
    end

    # The window an O_TRUNC write leaves open is proportional to how long the
    # write takes, so the padding is what makes this deterministic rather than a
    # 0.02%-per-read coin flip: with it, the unpatched store leaves the file
    # short for most of every write and this fails on the first few reads.
    #
    # How many times the reader got round its loop is deliberately not asserted.
    # It counts scheduler turns, not anything about atomicity — the property is
    # that no read ever saw a partial file — and on a loaded machine the same
    # correct code came round only 88 times and failed a `> 100` floor.
    it 'never shows a reader a partial file, however many writes it races' do
      store.create('meta3')
      store.write_meta('meta3', name: 'meta3', state: 'running', pad: 'p' * 200_000)
      writer = fork do
        200.times { |i| store.update_meta('meta3', rows: 20 + (i % 40), cols: 80 + (i % 40)) }
        exit!(0)
      end
      unreadable = 0
      until Process.waitpid(writer, Process::WNOHANG)
        unreadable += 1 unless store.read_meta('meta3')
      end

      expect(unreadable).to eq(0)
    end
  end

  describe 'a send that lands while the child is still talking' do
    # The characteristic failure measured against a real agent CLI is not a
    # truncated answer: it is the *previous* turn's answer, whole and
    # well-formed, which the caller cannot distinguish from a correct reply.
    # The child keeps printing for several seconds rather than replying once,
    # so the second send lands mid-output however long this process takes to
    # boot. The first version used a child that printed once and relied on the
    # second send starting within the settle window of it — which held locally
    # and failed on Ruby 3.0 in CI, where interpreter startup ate the window.
    # A test whose result depends on how fast the runner starts Ruby is not
    # testing the thing it names.
    def chattering_child
      ['ruby', '-e', <<~CHILD]
        STDOUT.sync = true
        while (line = STDIN.gets)
          25.times { print('.'); sleep 0.1 }
        end
      CHILD
    end

    it 'flags a send issued while the previous turn was still producing output' do
      start_session('busy1', chattering_child)
      session('send', '--name=busy1', '--no-wait', '--', 'first')
      wait_until(reason: 'the child to start printing') do
        session('read', '--name=busy1').data[:output].include?('.')
      end

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

  describe 'a rotation that cannot be written' do
    # `rotate_output` closed the caller's handle before it had a replacement to
    # hand back, so any later failure left the supervisor holding a closed handle
    # it had no idea was closed. `log_event`'s rescue then swallowed every write
    # for the rest of the session's life, silently.
    def unwritable(name)
      session_store = store
      session_store.create(name)
      session_store.write_meta(name, name: name, state: 'running')
      handle = session_store.open_output(name)
      handle.write("#{JSON.generate(event: 'output', ts: 1.0, bytes: 3, text: 'abc')}\n")
      File.chmod(0o500, session_store.session_dir(name))
      [session_store, handle]
    end

    it 'leaves the caller a handle it can still write to' do
      session_store, handle = unwritable('rotfail1')

      begin
        expect { session_store.rotate_output('rotfail1', handle, 3) }.to raise_error(SystemCallError)

        expect(handle).not_to be_closed
        expect { handle.write("still here\n") }.not_to raise_error
      ensure
        File.chmod(0o700, session_store.session_dir('rotfail1'))
      end
    end

    it 'leaves no half-written replacement behind' do
      session_store, handle = unwritable('rotfail2')

      begin
        expect { session_store.rotate_output('rotfail2', handle, 3) }.to raise_error(SystemCallError)

        expect(Dir.children(session_store.session_dir('rotfail2')).grep(/rotating/)).to be_empty
      ensure
        File.chmod(0o700, session_store.session_dir('rotfail2'))
      end
    end

    # The property that actually matters: the cursor `send` hands out has to stay
    # resolvable by `read`. Constants are shrunk so a rotation is reached in a few
    # hundred events rather than 32MB of them.
    it 'keeps the transcript level with the cursor right through the outage' do
      stub_const('Rune::Session::Store::MAX_LOG_BYTES', 300_000)
      stub_const('Rune::Session::Store::LOG_KEEP_BYTES', 250_000)
      session_store = store
      session_store.create('rotfail3')
      session_store.write_meta('rotfail3', name: 'rotfail3', state: 'running')
      supervisor = Rune::Session::Supervisor.new(name: 'rotfail3', command: ['true'], store: session_store)
      supervisor.instance_variable_set(:@output_log, session_store.open_output('rotfail3'))
      supervisor.instance_variable_set(:@log_bytes, 0)
      emit = ->(count) { count.times { supervisor.send(:append, 'z' * 3_000) } }
      on_disk = -> { Rune::Session::Transcript.load(session_store.output_path('rotfail3')).cursor }

      emit.call(120)
      File.chmod(0o500, session_store.session_dir('rotfail3'))
      begin
        emit.call(200)

        expect(on_disk.call).to eq(supervisor.send(:transcript_bytes))
      ensure
        File.chmod(0o700, session_store.session_dir('rotfail3'))
      end

      # And recording resumes rather than staying dead once the cause clears.
      emit.call(30)
      expect(on_disk.call).to eq(supervisor.send(:transcript_bytes))
    end

    # With the handle surviving, @log_bytes stays over the ceiling and every
    # further event would retry — and each retry seeks and scans the tail it
    # means to keep before discovering it cannot write (8_388_576 bytes, 4.8ms,
    # at the real constants) on the one thread that also drains the pty.
    it 'backs off instead of retrying on every event' do
      session_store = store
      session_store.create('rotfail4')
      session_store.write_meta('rotfail4', name: 'rotfail4', state: 'running')
      supervisor = Rune::Session::Supervisor.new(name: 'rotfail4', command: ['true'], store: session_store)
      supervisor.instance_variable_set(:@output_log, session_store.open_output('rotfail4'))
      attempts = 0
      allow(session_store).to receive(:rotate_output) do
        attempts += 1
        raise Errno::EACCES
      end

      10.times { supervisor.send(:rotate_log) }

      expect(attempts).to eq(1)
    end
  end

  describe 'a transcript write that fails outright' do
    # Distinct from a rotation that fails: the handle is fine, the filesystem
    # refuses. The in-memory cursor has already advanced, so a hole nothing
    # accounts for makes every cursor `send` hands out unresolvable by `read`,
    # permanently. Reproduced on a real full filesystem (RUNE_HOME on a 20MB
    # ramdisk): 852_000 bytes went unrecorded under `dropped: 0`, and freeing the
    # disk resumed logging over the hole without a word.
    #
    # `refusals` writes fail, then recover — the shape of a disk filling and
    # being freed — without needing a ramdisk to run in CI.
    def refusing_log(path, refusals:)
      # rubocop:disable Style/FileOpen -- handed to a supervisor that writes for
      # the rest of the example; the block form would close it first.
      real = File.open(path, File::WRONLY | File::CREAT | File::APPEND, 0o600)
      # rubocop:enable Style/FileOpen
      real.sync = true
      handle = Object.new
      handle.define_singleton_method(:closed?) { false }
      handle.define_singleton_method(:close) { real.close }
      handle.define_singleton_method(:write) do |payload|
        raise Errno::ENOSPC if (refusals -= 1) >= 0

        real.write(payload)
      end
      handle
    end

    def gapped_supervisor(name, refusals:)
      session_store = store
      session_store.create(name)
      session_store.write_meta(name, name: name, state: 'running')
      supervisor = Rune::Session::Supervisor.new(name: name, command: ['true'], store: session_store)
      log = refusing_log(session_store.output_path(name), refusals: refusals)
      supervisor.instance_variable_set(:@output_log, log)
      [supervisor, session_store]
    end

    it 'accounts for every byte the outage lost, once a write succeeds again' do
      supervisor, session_store = gapped_supervisor('gap1', refusals: 20)

      30.times { supervisor.send(:append, 'z' * 1_000) }

      loaded = Rune::Session::Transcript.load(session_store.output_path('gap1'))
      expect(loaded.cursor).to eq(supervisor.send(:transcript_bytes))
      expect(loaded.dropped).to eq(20_000)
    end

    it 'reports the hole in-band while it is still owed' do
      supervisor, = gapped_supervisor('gap2', refusals: 500)

      3.times { supervisor.send(:append, 'z' * 1_000) }

      expect(supervisor.send(:gap_field)).to eq(transcript_gap_bytes: 3_000)
    end

    it 'says nothing about a gap when there is none' do
      supervisor, = gapped_supervisor('gap3', refusals: 0)

      3.times { supervisor.send(:append, 'z' * 1_000) }

      expect(supervisor.send(:gap_field)).to eq({})
    end

    # A write that fails part-way leaves a fragment, and a fragment can be a
    # complete JSON object that merely never got its newline — which, once more
    # text is appended, silently swallows the next good record too. Measured on a
    # real full filesystem: one 4_938-byte line that parses as neither.
    it 'keeps a torn fragment from swallowing the record that follows it' do
      session_store = store
      session_store.create('gap4')
      session_store.write_meta('gap4', name: 'gap4', state: 'running')
      path = session_store.output_path('gap4')
      supervisor = Rune::Session::Supervisor.new(name: 'gap4', command: ['true'], store: session_store)
      # rubocop:disable Style/FileOpen -- as above.
      real = File.open(path, File::WRONLY | File::CREAT | File::APPEND, 0o600)
      # rubocop:enable Style/FileOpen
      real.sync = true
      torn = false
      handle = Object.new
      handle.define_singleton_method(:closed?) { false }
      handle.define_singleton_method(:write) do |payload|
        next real.write(payload) if torn

        torn = true
        # Half a record lands, then the write fails: exactly what ENOSPC does.
        real.write(payload.byteslice(0, payload.bytesize / 2))
        raise Errno::ENOSPC
      end
      supervisor.instance_variable_set(:@output_log, handle)

      supervisor.send(:append, 'a' * 1_000)
      supervisor.send(:append, 'b' * 1_000)

      loaded = Rune::Session::Transcript.load(path)
      # The second append survives whole; only the torn first one is lost, and
      # its bytes are accounted for rather than vanishing.
      expect(loaded.text).to include('b' * 1_000)
      expect(loaded.cursor).to eq(supervisor.send(:transcript_bytes))
    end

    # Rotation's head event is `total_output - kept`, so anything the kept region
    # accounts for and `output_bytes_from` does not gets counted twice.
    it 'counts a truncated event inside the kept region' do
      session_store = store
      session_store.create('gap5')
      path = session_store.output_path('gap5')
      lines = [JSON.generate(event: 'output', ts: 1.0, bytes: 10, text: 'x' * 10),
               JSON.generate(event: 'truncated', ts: 1.0, dropped_bytes: 400_000),
               JSON.generate(event: 'output', ts: 1.0, bytes: 10, text: 'y' * 10)]
      File.write(path, lines.map { |line| "#{line}\n" }.join)

      expect(session_store.output_bytes_from(path, 0)).to eq(400_020)
    end

    it 'does not count a torn fragment the reader will skip' do
      session_store = store
      session_store.create('gap6')
      path = session_store.output_path('gap6')
      fragment = JSON.generate(event: 'output', ts: 1.0, bytes: 999, text: 'z' * 999).byteslice(0, 40)
      File.binwrite(path, "#{fragment}#{Rune::Session::Supervisor::TORN_MARKER}" \
                          "#{JSON.generate(event: 'output', ts: 1.0, bytes: 10, text: 'y' * 10)}\n")

      expect(session_store.output_bytes_from(path, 0)).to eq(10)
    end
  end

  describe 'teardown records the child as gone only once it is' do
    # `cleanup` wrote `state: 'exited'` before it terminated the child, so a
    # supervisor dying in that window left a concluded record beside a live
    # process — and any check that trusted the state field was blind to exactly
    # the case it existed for. `conclude` already kills first on the normal path;
    # this is the abnormal one, reached when no rescue in `run` did.
    it 'has already reaped the child when "exited" reaches meta' do
      session_store = store
      session_store.create('order1')
      session_store.write_meta('order1', name: 'order1', state: 'running')
      reader, writer, pid = PTY.spawn('ruby', '-e', 'Signal.trap("HUP","IGNORE"); loop { sleep 1 }')
      supervisor = Rune::Session::Supervisor.new(name: 'order1', command: ['true'], store: session_store)
      supervisor.instance_variable_set(:@child_pid, pid)
      supervisor.instance_variable_set(:@output_log, session_store.open_output('order1'))
      alive_when_recorded = nil
      recorder = session_store.method(:update_meta)
      allow(session_store).to receive(:update_meta) do |name, fields|
        alive_when_recorded = Rune::Session::Store.alive?(pid) if fields[:state] == 'exited'
        recorder.call(name, fields)
      end

      begin
        supervisor.send(:cleanup, nil)
      ensure
        [reader, writer].each { |io| io.close unless io.closed? }
      end

      expect(alive_when_recorded).to be false
      expect(session_store.read_meta('order1')[:state]).to eq('exited')
      expect(Rune::Session::Store.alive?(pid)).to be false
    end
  end

  describe 'a child that outlived its supervisor' do
    # Reported, never refused. An earlier attempt refused the archive and sent
    # the caller to `rune session stop`, which SIGKILLs the recorded pid's whole
    # process group — so whenever its liveness test was wrong about a recycled
    # pid, the remedy killed a stranger. It asked the process *group* on the
    # premise that a recycled pid sits in its parent's group; measured here,
    # 87.9% of live processes lead their own group.
    def survivor = ['ruby', '-e', 'Signal.trap("HUP","IGNORE"); loop { sleep 1 }']

    # A pid that is certainly dead: spawned and reaped, so nothing of ours holds
    # it and nothing has had the chance to reuse it yet.
    def reaped_pid
      pid = Process.spawn('true', out: File::NULL, err: File::NULL)
      Process.wait(pid)
      pid
    end

    # A session whose supervisor is gone, pointed at `child` as its child.
    def orphaned_session(name, child, started: nil)
      session_store = store
      session_store.create(name)
      session_store.write_meta(name, name: name, command: ['x'], state: 'running',
                                     child_pid: child, supervisor_pid: reaped_pid,
                                     child_started_at: started || Rune::Session::Store.process_start_time(child))
      session_store
    end

    def listed(name)
      session('list').data[:sessions].find { |entry| entry[:name] == name }
    end

    it 'names the live child in list' do
      child = Process.spawn(*survivor, out: File::NULL, err: File::NULL)
      orphaned_session('orph1', child)

      begin
        expect(listed('orph1')[:orphaned_child_pid]).to eq(child)
      ensure
        Process.kill('KILL', child)
        Process.wait(child)
      end
    end

    # The blind spot of the check this replaces: it skipped any session recorded
    # exited/stopped/failed, which is precisely where a supervisor that died
    # mid-teardown leaves its record.
    it 'names it even when meta claims the session already exited' do
      child = Process.spawn(*survivor, out: File::NULL, err: File::NULL)
      session_store = orphaned_session('orph2', child)
      session_store.update_meta('orph2', state: 'exited', exit_code: 0)

      begin
        expect(listed('orph2')[:orphaned_child_pid]).to eq(child)
      ensure
        Process.kill('KILL', child)
        Process.wait(child)
      end
    end

    it 'names it on the archive reply and archives anyway' do
      child = Process.spawn(*survivor, out: File::NULL, err: File::NULL)
      orphaned_session('orph3', child)

      begin
        result = session('archive', '--name=orph3')

        expect(result).to be_success
        expect(result.data[:orphaned_child_pid]).to eq(child)
        expect(result.data[:archived_to]).to include('orph3')
        expect(Rune::Session::Store.alive?(child)).to be true
      ensure
        Process.kill('KILL', child)
        Process.wait(child)
      end
    end

    # The case the abandoned group check got wrong. A live process that merely
    # wears the recorded number is not this session's child, and saying it is
    # would point an operator at a stranger.
    it 'says nothing about a live process that only wears the recorded number' do
      stranger = Process.spawn(*survivor, out: File::NULL, err: File::NULL, pgroup: true)
      orphaned_session('recyc1', stranger, started: 'Thu Jan  1 00:00:00 1970')

      begin
        expect(Process.getpgid(stranger)).to eq(stranger)
        expect(listed('recyc1')[:orphaned_child_pid]).to be_nil
        expect(session('archive', '--name=recyc1').data[:orphaned_child_pid]).to be_nil
        expect(Rune::Session::Store.alive?(stranger)).to be true
      ensure
        Process.kill('KILL', stranger)
        Process.wait(stranger)
      end
    end

    # No recorded identity is not evidence of an orphan. Sessions started before
    # the field existed, and any supervisor that died before writing it, answer
    # "unknown" — which is silence, not a guess from the bare pid.
    it 'says nothing when the child identity was never recorded' do
      child = Process.spawn(*survivor, out: File::NULL, err: File::NULL)
      session_store = store
      session_store.create('legacy1')
      session_store.write_meta('legacy1', name: 'legacy1', command: ['x'], state: 'running',
                                          child_pid: child, supervisor_pid: reaped_pid)

      begin
        expect(listed('legacy1')[:orphaned_child_pid]).to be_nil
      ensure
        Process.kill('KILL', child)
        Process.wait(child)
      end
    end

    # A human on a TTY gets the warning as a line of its own. Folded into the
    # archive envelope it would be one key in a JSON blob, which is exactly where
    # a person skimming a successful archive would not look.
    it 'warns a human archiving a session that still has a live child' do
      io = StringIO.new
      session_command.human_render({ action: 'archive', name: 'x', archived_to: 'y',
                                     orphaned_child_pid: 4242 }, io)

      expect(io.string).to include('child pid 4242 is still running')
      expect(io.string).to include('"archived_to":"y"')
    end

    it 'says nothing extra when an archive leaves nothing behind' do
      io = StringIO.new
      session_command.human_render({ action: 'archive', name: 'x', archived_to: 'y' }, io)

      expect(io.string).to eq(%({"name":"x","archived_to":"y"}\n))
    end

    it 'marks the orphan in a human session list' do
      io = StringIO.new
      session_command.human_render({ action: 'list',
                                     sessions: [{ name: 's', state: 'dead', command: ['x'],
                                                  orphaned_child_pid: 4242 }] }, io)

      expect(io.string).to include('child pid 4242 is still running with no supervisor')
    end

    it 'says nothing about a session whose supervisor is alive and well' do
      start_session('healthy1', survivor)

      expect(listed('healthy1')[:state]).to eq('running')
      expect(listed('healthy1')[:orphaned_child_pid]).to be_nil
    end

    # End to end, with a real supervisor really killed. `start` returns before
    # the child's interpreter has installed its trap, so the pty hangup would
    # otherwise kill the child and there would be no orphan to find.
    it 'reports a child left behind by a SIGKILLed supervisor' do
      result = start_session('orph4', survivor)
      child = result.data[:child_pid]
      supervisor = result.data[:supervisor_pid]
      wait_until(reason: 'the child to install its HUP trap') do
        (store.read_meta('orph4') || {})[:child_started_at]
      end
      sleep 0.8
      Process.kill('KILL', supervisor)
      wait_until(reason: 'the supervisor to die') { !Rune::Session::Store.alive?(supervisor) }

      expect(Rune::Session::Store.alive?(child)).to be true
      expect(listed('orph4')[:orphaned_child_pid]).to eq(child)
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

    # The child ends up at the default, but may observe 0x0 first. `PTY.spawn`
    # returns the master only once the child is already running, so
    # `apply_window_size` cannot land before a child that reads its winsize
    # immediately — it gets the size via the SIGWINCH that follows instead. Seen
    # on a Ruby 3.1 CI runner as `SIZE:[0, 0]` followed by `RESIZED:[40, 120]`,
    # where every other version won the race. Asserting only the first line
    # asserted the scheduler, so this asserts the guarantee rune actually makes:
    # the child is at the default, by whichever of the two paths delivered it.
    it 'starts headless at the documented default' do
      start_session('s35', size_reporter)
      default = "[#{Rune::Session::Supervisor::DEFAULT_ROWS}, #{Rune::Session::Supervisor::DEFAULT_COLUMNS}]"

      wait_until(reason: 'the child to report the default size') do
        session('read', '--name=s35').data[:output].include?(default)
      end

      output = session('read', '--name=s35').data[:output]
      expect(output).to include("SIZE:#{default}").or include("RESIZED:#{default}")
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
