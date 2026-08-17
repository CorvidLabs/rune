# frozen_string_literal: true

# A real orphan, and what rune says about it.
#
# SIGKILLs a live supervisor, which leaves its child running and reparented to
# pid 1 while still holding the pty. `list` and `archive` must both name that
# pid, and must still name it when the dead supervisor left `state: exited`
# behind — the case a state-gated check waves through.
#
# The child ignores SIGHUP, and that is not harness convenience. Closing the pty
# master hangs up the child's controlling terminal, so a plain `sleep` dies with
# its supervisor and there is no orphan to find. The processes that actually
# survive are the ones that ignore it or sit in their own session: agent CLI
# wrappers, node workers, MCP servers — which is the whole population this
# reports on.
#
# The negative half matters more than the positive one. A stranger wearing a
# recycled child pid must NOT be reported, because the earlier attempt at this
# refused the archive and sent callers to `rune session stop`, which SIGKILLs
# the recorded pid's entire process group.
#
# Usage: ruby harnesses/orphan_report.rb

require 'tmpdir'
require 'json'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
SURVIVOR = ['ruby', '-e', 'Signal.trap("HUP","IGNORE"); loop { sleep 1 }'].freeze
# `start` returns when the *session* is ready, which is before the child's own
# interpreter has finished booting. Killing the supervisor inside that window
# hangs the pty up before `Signal.trap` has run, the default action applies and
# the child dies — which reads exactly like "orphans do not happen". Measured:
# 0/3 trapping children survived with no delay, 3/3 with this one.
BOOT = 0.8

# `--json` must go *before* the first `--`: rune recognizes its own flags only
# up to that point, and appending it sent `--json` to the child instead, which
# made `sleep 600 --json` exit immediately. (Harness bug, found the hard way.)
def rune(home, *args)
  split = args.index('--') || args.size
  argv = args[0...split] + ['--json'] + args[split..]
  out = IO.popen([{ 'RUNE_HOME' => home }, RbConfig.ruby, '-I', "#{ROOT}/lib", "#{ROOT}/bin/rune",
                  *argv, { err: %i[child out] }], &:read)
  JSON.parse(out)
rescue JSON::ParserError
  { 'error' => out }
end

def field(reply, *path) = reply.dig('data', *path)

def alive?(pid)
  return false unless pid

  Process.kill(0, Integer(pid))
  true
rescue StandardError
  false
end

def kill!(pid, signal = 'KILL')
  Process.kill(signal, Integer(pid))
rescue StandardError
  nil
end

def meta_path(home, name) = Dir.glob(File.join(home, 'projects', '*', 'sessions', name, 'meta.json')).first

def rewrite_meta(home, name, fields, drop: [])
  path = meta_path(home, name)
  meta = JSON.parse(File.read(path)).merge(fields)
  drop.each { |key| meta.delete(key) }
  File.write(path, JSON.generate(meta))
  meta
end

FAILURES = []
def check(label, got, want)
  ok = got == want
  FAILURES << label unless ok
  printf("%-56s %-20s %s\n", label, got.inspect, ok ? 'ok' : "WANT #{want.inspect}")
end

Dir.mktmpdir('rune-orphan') do |home|
  # ---- 1. a genuine orphan is reported, and nothing is blocked.
  start = rune(home, 'session', 'start', '--name=orph', '--', *SURVIVOR)
  child = field(start, 'child_pid')
  supervisor = field(start, 'supervisor_pid')
  puts "started: supervisor=#{supervisor} child=#{child} " \
       "pgid=#{Process.getpgid(child)} (leads own group: #{Process.getpgid(child) == child})"

  sleep BOOT
  kill!(supervisor)
  sleep 0.6
  check('supervisor dead', alive?(supervisor), false)
  check('child survived its supervisor', alive?(child), true)
  check('child reparented to pid 1', `ps -o ppid= -p #{child}`.strip, '1')

  listed = field(rune(home, 'session', 'list'), 'sessions').first
  check('list reports the orphan pid', listed['orphaned_child_pid'], child)
  check('list state is still just "dead"', listed['state'], 'dead')

  # The blind spot of a state-gated check: a supervisor that recorded `exited`
  # and then failed to kill its child. Forged directly, because the real window
  # inside `cleanup` is microseconds wide.
  rewrite_meta(home, 'orph', { 'state' => 'exited', 'exit_code' => 0 })
  listed = field(rune(home, 'session', 'list'), 'sessions').first
  check('reported even when meta claims state=exited', listed['orphaned_child_pid'], child)

  archived = rune(home, 'session', 'archive', '--name=orph')
  check('archive succeeded (nothing blocked)', !field(archived, 'archived_to').nil?, true)
  check('archive reports the orphan pid', field(archived, 'orphaned_child_pid'), child)
  check('child survived the archive', alive?(child), true)
  kill!(child)

  # ---- 2. a stranger wearing a recycled number must not be reported.
  #
  # Ordered the way real pid reuse is ordered: the session's child dies, and only
  # then does something else come to wear its number. `pgroup: true` makes the
  # stranger a process-group leader, which is the case the abandoned group-based
  # test got wrong — 87.9% of live processes on this machine lead their own group,
  # so `kill(0, -pid)` would have answered "alive" here and sent the operator to
  # `rune session stop`, which SIGKILLs that whole group.
  rune(home, 'session', 'start', '--name=recyc', '--', *SURVIVOR)
  sleep BOOT
  meta = JSON.parse(File.read(meta_path(home, 'recyc')))
  kill!(meta['supervisor_pid'])
  kill!(meta['child_pid'])
  # More than one second, because `lstart` resolves to the second: a stranger
  # that started in the same second as the child it replaced is genuinely
  # indistinguishable. Real reuse cannot be that fast — the pid space has to wrap
  # first, measured at ~40s of sustained spawning on this machine — but the
  # harness could be, and was.
  sleep 1.4
  stranger = Process.spawn(*SURVIVOR, out: File::NULL, err: File::NULL, pgroup: true)
  sleep 0.3
  check('stranger leads its own group (the 87.9% case)', Process.getpgid(stranger) == stranger, true)
  group_answer = begin
    Process.kill(0, -stranger)
    true
  rescue StandardError
    false
  end
  check('  a group question would have said "alive"', group_answer, true)

  rewrite_meta(home, 'recyc', { 'child_pid' => stranger })
  listed = field(rune(home, 'session', 'list'), 'sessions').find { |s| s['name'] == 'recyc' }
  check('  but the identity test does NOT report it', listed['orphaned_child_pid'], nil)
  archived = rune(home, 'session', 'archive', '--name=recyc')
  check('  archive of it says nothing', field(archived, 'orphaned_child_pid'), nil)
  check('  archive still succeeded', !field(archived, 'archived_to').nil?, true)
  check('  stranger untouched throughout', alive?(stranger), true)
  kill!(stranger)
  Process.wait(stranger)

  # ---- 3. no recorded identity => silence, not a guess from the bare pid.
  rune(home, 'session', 'start', '--name=legacy', '--', *SURVIVOR)
  meta = JSON.parse(File.read(meta_path(home, 'legacy')))
  sleep BOOT
  kill!(meta['supervisor_pid'])
  sleep 0.6
  rewrite_meta(home, 'legacy', {}, drop: ['child_started_at'])
  listed = field(rune(home, 'session', 'list'), 'sessions').find { |s| s['name'] == 'legacy' }
  check('no recorded identity => silent', listed['orphaned_child_pid'], nil)
  check('  though its child really is alive', alive?(meta['child_pid']), true)
  kill!(meta['child_pid'])

  # ---- 4. a healthy running session is not an orphan.
  rune(home, 'session', 'start', '--name=healthy', '--', *SURVIVOR)
  listed = field(rune(home, 'session', 'list'), 'sessions').find { |s| s['name'] == 'healthy' }
  check('live session is not reported', listed['orphaned_child_pid'], nil)
  check('  and is running', listed['state'], 'running')
  rune(home, 'session', 'stop', '--name=healthy')
  listed = field(rune(home, 'session', 'list'), 'sessions').find { |s| s['name'] == 'healthy' }
  check('cleanly stopped session is not reported', listed['orphaned_child_pid'], nil)
end

puts(FAILURES.empty? ? 'PASS' : "FAIL: #{FAILURES.join(' | ')}")
exit(FAILURES.empty? ? 0 : 1)
