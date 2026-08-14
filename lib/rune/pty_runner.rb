# frozen_string_literal: true

# The pty stdlib is unavailable on some platforms (e.g. Windows) and in some
# sandboxed/containerized environments. Rescuing here keeps the rest of rune
# (version, help, anything not touching PTYRunner) usable even when it's
# missing, instead of crashing the whole binary at boot with a bare LoadError.
begin
  require 'pty'
  PTY_LOAD_ERROR = nil
rescue LoadError => e
  PTY_LOAD_ERROR = e
end

require 'timeout'
require 'shellwords'
# IO#wait_readable/#wait_writable are provided by this stdlib extension, not
# by 'pty' itself. On Ruby versions where it isn't already autoloaded as part
# of core IO, every #run would otherwise crash with a raw NoMethodError the
# moment read_pty_stream calls #wait_readable — found via a real triage
# against a Ruby 3.1 install, inside this gem's own declared >= 3.0 support
# range.
require 'io/wait'
require_relative 'parsers/text_sanitizer'
require_relative 'parsers/prompt_detector'
require_relative 'signal_handler'
require_relative 'utf8_stream_decoder'
require_relative 'output_limiter'

module Rune
  # rubocop:disable Metrics/ClassLength -- grew past the limit from the timeout-kill and io/wait
  # fixes; the spawn/read/signal-forwarding logic here is tightly coupled and splitting it across
  # files for a line-count metric alone would hurt readability more than it helps.
  class PTYRunner
    attr_reader :command, :input, :script, :timeout_seconds, :on_output, :max_output_bytes, :tail_lines,
                :separate_streams

    # Raised when the OS itself refuses to allocate a pty (device exhaustion,
    # a sandbox/container denying it), as opposed to Errno::ENOENT/EACCES from
    # exec'ing the *target* command, which are a property of the wrapped
    # command and already handled as ordinary exit codes in execute_pty.
    PTY_ALLOCATION_ERRORS = [Errno::ENXIO, Errno::EMFILE, Errno::ENFILE, Errno::EPERM].freeze

    def self.pty_available? = PTY_LOAD_ERROR.nil?

    # rubocop:disable Metrics/ParameterLists -- six independent execution knobs (input, script,
    # timeout, the two mutually-exclusive output-bounding options, and the opt-in separate-streams
    # mode) read more clearly as named kwargs at the call site (PTYRunner.new(cmd, max_output_bytes:
    # N)) than folded into one options hash; matches this file's existing tolerance for organic
    # growth (see ClassLength disable above).
    def initialize(command, input: nil, script: nil, timeout_seconds: 30, max_output_bytes: nil, tail_lines: nil,
                   separate_streams: false, &on_output)
      # rubocop:enable Metrics/ParameterLists
      @command = command.is_a?(Array) ? Shellwords.join(command) : command.to_s
      @spawn_arguments = command.is_a?(Array) ? command.map(&:to_s) : [@command]
      @input = input
      @script = script
      @timeout_seconds = timeout_seconds
      @max_output_bytes = max_output_bytes
      @tail_lines = tail_lines
      @separate_streams = separate_streams
      @on_output = on_output
    end

    def run
      return pty_unavailable_result unless self.class.pty_available?
      return separate_streams_script_conflict if separate_streams && script

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw_output, exit_code, prompt_detected, stdout_buffer, stderr_buffer = execute_pty

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
      data = build_result_data(raw_output, exit_code, prompt_detected, duration_ms, [stdout_buffer, stderr_buffer])

      Result.success(data, exit_code: exit_code || 0)
    rescue *PTY_ALLOCATION_ERRORS => e
      Result.failure("PTY allocation failed at runtime: #{e.class} - #{e.message}. Platform/sandbox may restrict it.")
    rescue StandardError => e
      Result.failure("Failed to execute command '#{command}': #{e.message}")
    end

    def detect_prompt?(line) = Parsers::PromptDetector.detect?(line)

    private

    def pty_unavailable_result
      Result.failure("PTY unavailable: pty stdlib failed to load (#{PTY_LOAD_ERROR&.message}).")
    end

    def separate_streams_script_conflict
      Result.failure('separate_streams: true cannot be combined with script: — the interactive ' \
                     'wait_for/send_keys DSL is only supported against the merged single-stream view.')
    end

    # Builds the full result data: the merged clean_output/raw_output view (bounded by
    # --max-output/--tail if requested), plus clean_stdout/clean_stderr when separate_streams was
    # requested. Neither option changes the shape when unset — the result data is byte-for-byte
    # unchanged from the original single-stream, unbounded-output contract by default.
    def build_result_data(raw_output, exit_code, prompt_detected, duration_ms, stream_buffers)
      clean_output = Parsers::TextSanitizer.strip_ansi(raw_output)
      clean_output, raw_output, limit_data = apply_output_limit(clean_output, raw_output)

      data = { command: command, exit_code: exit_code || 0, clean_output: clean_output,
               raw_output: raw_output, prompt_detected: prompt_detected, duration_ms: duration_ms }.merge(limit_data)
      return data unless separate_streams

      stdout_buffer, stderr_buffer = stream_buffers
      data.merge(clean_stdout: Parsers::TextSanitizer.strip_ansi(stdout_buffer),
                 clean_stderr: Parsers::TextSanitizer.strip_ansi(stderr_buffer))
    end

    # Bounds clean_output/raw_output when --max-output or --tail was requested. Both fields are
    # bounded to the same budget independently, but the reported omitted_bytes/omitted_lines count
    # reflects clean_output only (the primary agent-facing field) — raw_output still includes ANSI
    # codes and cursor movements, so its own omitted count is not necessarily identical and isn't
    # separately surfaced. Returns [clean_output, raw_output, extra_data] where extra_data is {}
    # (no new keys at all) unless one of the options is set — the result data shape is
    # byte-for-byte unchanged by default.
    def apply_output_limit(clean_output, raw_output)
      if max_output_bytes
        clean_output, omitted = OutputLimiter.truncate_middle(clean_output, max_output_bytes)
        raw_output, = OutputLimiter.truncate_middle(raw_output, max_output_bytes)
        [clean_output, raw_output, { truncated: omitted.positive?, omitted_bytes: omitted }]
      elsif tail_lines
        clean_output, omitted = OutputLimiter.tail_lines(clean_output, tail_lines)
        raw_output, = OutputLimiter.tail_lines(raw_output, tail_lines)
        [clean_output, raw_output, { truncated: omitted.positive?, omitted_lines: omitted }]
      else
        [clean_output, raw_output, {}]
      end
    end

    def execute_pty
      raw_output = +''
      stdout_buffer = separate_streams ? +'' : nil
      stderr_buffer = separate_streams ? +'' : nil
      exit_code = nil
      prompt_detected = false
      spawned_pid = nil

      Timeout.timeout(timeout_seconds) do
        prompt_detected, exit_code = spawn_for_mode(raw_output, stdout_buffer, stderr_buffer) do |pid|
          spawned_pid = pid
        end
      end

      [raw_output, exit_code, prompt_detected, stdout_buffer, stderr_buffer]
    rescue Errno::ENOENT then ["Command not found: #{command}", 127, false, stdout_buffer, stderr_buffer]
    rescue Errno::EACCES then ["Permission denied: #{command}", 126, false, stdout_buffer, stderr_buffer]
    rescue Timeout::Error
      # Timeout.timeout only interrupts Ruby's control flow — the spawned OS
      # process keeps running as an orphan unless killed explicitly here.
      kill_orphaned_child(spawned_pid)
      ["#{raw_output}\n[rune] Execution timed out after #{timeout_seconds} seconds", 124, false, stdout_buffer,
       stderr_buffer]
    rescue PTY::ChildExited then [raw_output, 0, prompt_detected, stdout_buffer, stderr_buffer]
    end

    def spawn_for_mode(raw_output, stdout_buffer, stderr_buffer, &on_pid)
      if separate_streams
        spawn_and_stream_separate(raw_output, stdout_buffer, stderr_buffer, &on_pid)
      else
        spawn_and_stream(raw_output, &on_pid)
      end
    end

    def spawn_and_stream(raw_output, &on_pid)
      exit_code = nil
      prompt_detected = false
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }

      PTY.spawn(env, *@spawn_arguments) do |r, w, pid|
        on_pid&.call(pid)
        SignalHandler.with_traps(pid) do |forward_signal|
          write_input(w, input) if input
          prompt_detected = read_pty_stream(r, w, raw_output, forward_signal)
          exit_code = wait_for_process(pid)
        end
      end
      [prompt_detected, exit_code]
    end

    # Opt-in mode for issue #15: stdout keeps a real PTY (the child still believes it has a
    # terminal on its primary output), but stderr is redirected to a plain pipe instead of sharing
    # the same pty slave. This is what makes clean_stdout/clean_stderr distinguishable at all — a
    # single pty is one stream by construction. Trade-off, and why this is opt-in rather than the
    # default: the child no longer gets true controlling-terminal/session-leader semantics (rune's
    # own signal forwarding doesn't depend on that — see SignalHandler — but a child relying on
    # terminal-driven job control itself would notice).
    def spawn_and_stream_separate(raw_output, stdout_buffer, stderr_buffer, &on_pid)
      exit_code = nil
      prompt_detected = false

      PTY.open do |master, slave|
        err_r, err_w = IO.pipe
        pid = spawn_with_separated_stderr(slave, err_w, &on_pid)
        slave.close
        err_w.close
        begin
          SignalHandler.with_traps(pid) do |forward_signal|
            write_input(master, input) if input
            streams = [{ reader: master, buffer: stdout_buffer }, { reader: err_r, buffer: stderr_buffer }]
            prompt_detected = read_separate_streams(streams, raw_output, forward_signal)
            exit_code = wait_for_process(pid)
          end
        ensure
          err_r.close unless err_r.closed?
        end
      end
      [prompt_detected, exit_code]
    end

    def spawn_with_separated_stderr(slave, err_w, &on_pid)
      env = { 'PAGER' => 'cat', 'GIT_PAGER' => 'cat' }
      pid = Process.spawn(env, *@spawn_arguments, in: slave, out: slave, err: err_w)
      on_pid&.call(pid)
      pid
    end

    # SIGKILL, not SIGTERM: the process already overran its allotted time, so
    # there's no value giving it another chance to ignore a softer signal.
    def kill_orphaned_child(pid)
      return unless pid

      Process.kill('KILL', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def wait_for_process(pid)
      _, status = Process.wait2(pid)
      status.exitstatus || (status.signaled? ? 128 + status.termsig : 1)
    rescue Errno::ECHILD
      0
    end

    def write_input(writer, data)
      return if data.nil? || data.empty?

      writable = writer.wait_writable(2.0) rescue nil # rubocop:disable Style/RescueModifier
      return unless writable

      writer.write_nonblock(data)
      writer.flush
    rescue StandardError
      nil
    end

    # Polls with a short readable-wait rather than blocking indefinitely on
    # readpartial, so a caught signal gets forwarded promptly instead of
    # waiting for the next chunk of child output (which may never come).
    def read_pty_stream(reader, writer, output_buffer, forward_signal)
      prompt_found = false
      script_step_index = 0
      decoder = UTF8StreamDecoder.new
      loop do
        forward_signal.call
        next unless reader.wait_readable(0.2)

        chunk = decoder.decode(reader.readpartial(4096))
        prompt_found, script_step_index = consume_output_chunk(
          chunk, output_buffer, writer, prompt_found, script_step_index
        )
      end
    rescue Errno::EIO, EOFError, PTY::ChildExited, Errno::EPIPE
      prompt_found, = consume_output_chunk(
        decoder.finish, output_buffer, writer, prompt_found, script_step_index
      )
      prompt_found
    end

    # Multiplexes N independent readers (stdout's pty, stderr's pipe) with IO.select instead of
    # read_pty_stream's single #wait_readable — there is no script/writer coupling here
    # (separate_streams: true and script: are mutually exclusive, checked in #run), just each
    # stream decoded and appended to its own buffer plus the shared merged raw_output. `streams` is
    # `[{reader:, buffer:}, ...]`; a `decoder:` is added to each entry here.
    def read_separate_streams(streams, raw_output, forward_signal)
      prompt_found = false
      streams.each { |stream| stream[:decoder] = UTF8StreamDecoder.new }
      open_streams = streams.dup

      until open_streams.empty?
        forward_signal.call
        prompt_found = poll_ready_streams(open_streams, raw_output) || prompt_found
      end

      prompt_found
    end

    def poll_ready_streams(open_streams, raw_output)
      ready, = IO.select(open_streams.map { |stream| stream[:reader] }, nil, nil, 0.2)
      return false unless ready

      open_streams.select { |stream| ready.include?(stream[:reader]) }.reduce(false) do |found, stream|
        consume_stream_chunk(stream, raw_output, open_streams) || found
      end
    end

    def consume_stream_chunk(stream, raw_output, open_streams)
      decoded = stream[:decoder].decode(stream[:reader].readpartial(4096))
      append_decoded_chunk(decoded, stream[:buffer], raw_output)
    rescue Errno::EIO, EOFError, PTY::ChildExited, Errno::EPIPE
      open_streams.delete(stream)
      append_decoded_chunk(stream[:decoder].finish, stream[:buffer], raw_output)
    end

    def append_decoded_chunk(decoded, buffer, raw_output)
      return false if decoded.empty?

      buffer << decoded
      raw_output << decoded
      on_output&.call(decoded)
      decoded.split("\n").any? { |line| detect_prompt?(line) }
    end

    def consume_output_chunk(chunk, output_buffer, writer, prompt_found, script_step_index)
      return [prompt_found, script_step_index] if chunk.empty?

      output_buffer << chunk
      on_output&.call(chunk)
      prompt_found ||= chunk.split("\n").any? { |line| detect_prompt?(line) }
      script_step_index = process_script_steps(script_step_index, output_buffer, writer) if script
      [prompt_found, script_step_index]
    end

    def process_script_steps(current_index, buffer, writer)
      return current_index if script.nil?

      while current_index < script.steps.size
        step = script.steps[current_index]
        case step.type
        when :wait_for then break unless buffer.match?(step.payload)
        when :send_keys then write_input(writer, step.payload)
        when :pause then sleep(step.payload)
        end
        current_index += 1
      end
      current_index
    end
  end
  # rubocop:enable Metrics/ClassLength
end
