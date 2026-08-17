# frozen_string_literal: true

# A rotation that cannot happen, on a real unwritable directory.
#
# `rotate_output` used to close the caller's handle before it had a replacement
# to hand back, so a rotation that failed after that point left the supervisor
# holding a *closed* handle it had no idea was closed. `log_event`'s own rescue
# then swallowed every subsequent write, silently and permanently, for the rest
# of the session's life — and the cursor `send` hands out kept advancing over a
# transcript that had stopped growing.
#
# This drives real output through a real EACCES (chmod 0500 on the session
# directory, so the rename and the temp file both fail) and asks the only
# question that matters: does the transcript on disk still agree with the cursor?
#
# Usage:  ruby harnesses/rotation_eacces.rb
#         LIB=/path/to/other/lib ruby harnesses/rotation_eacces.rb
#
# Reads as PASS only when the skew is 0 in all three phases and the handle
# survives the outage.

lib = ENV.fetch('LIB', File.expand_path('../lib', __dir__))
require 'tmpdir'
require 'json'
require "#{lib}/rune/session/store"
require "#{lib}/rune/session/supervisor"
require "#{lib}/rune/session/transcript"

Store = Rune::Session::Store

# Small enough that a few hundred 3KB events force several rotations.
{ MAX_LOG_BYTES: 300_000, LOG_KEEP_BYTES: 250_000 }.each do |const, value|
  Store.send(:remove_const, const)
  Store.const_set(const, value)
end

CHUNK = 3_000

Dir.mktmpdir('rune-rotation-eacces') do |home|
  store = Store.new(home: home, project: 'harness')
  store.create('rot')
  store.write_meta('rot', name: 'rot', state: 'running')

  # A supervisor with a real store and a real log handle, driven directly. No
  # pty: the subject is the write path, and a child would only add scheduling
  # noise to a measurement of byte accounting.
  supervisor = Rune::Session::Supervisor.new(name: 'rot', command: ['true'], store: store)
  supervisor.instance_variable_set(:@output_log, store.open_output('rot'))
  supervisor.instance_variable_set(:@log_bytes, 0)

  attempts = 0
  store.define_singleton_method(:rotate_output) do |*args|
    attempts += 1
    super(*args)
  end

  emit = ->(count) { count.times { supervisor.send(:append, 'z' * CHUNK) } }
  cursor = -> { supervisor.send(:transcript_bytes) }
  disk = -> { Rune::Session::Transcript.load(store.output_path('rot')).cursor }
  report = lambda do |label|
    handle = supervisor.instance_variable_get(:@output_log)
    printf("%-20s cursor=%-9d transcript=%-9d skew=%+d  handle_closed=%s\n",
           label, cursor.call, disk.call, disk.call - cursor.call,
           handle.nil? ? 'nil' : handle.closed?)
    disk.call - cursor.call
  end

  emit.call(120)
  attempts = 0
  healthy = report.call('healthy:')

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  File.chmod(0o500, store.session_dir('rot'))
  emit.call(200)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  during = report.call('EACCES:')
  printf("%-20s %d rotation attempts over 200 events in %.2fs\n", '', attempts, elapsed)

  File.chmod(0o700, store.session_dir('rot'))
  emit.call(30)
  after = report.call('writable again:')

  leftovers = Dir.glob(File.join(store.session_dir('rot'), '*.rotating')).size
  printf("%-20s %d\n", 'leftover .rotating:', leftovers)
  ok = [healthy, during, after].all?(&:zero?) && leftovers.zero?
  puts(ok ? 'PASS' : 'FAIL')
ensure
  Dir.glob(File.join(home, '**/')).each do |dir|
    File.chmod(0o700, dir)
  rescue SystemCallError
    next
  end
end
