# Repeatable harness for the --wait-for-regex scaling blocker.
#
# For each size: start a session on blaster.rb, send one turn that makes the
# child emit N MB and then print a marker, and report wall clock, the settle
# flags, and how many bytes the supervisor actually drained.
#
#   ruby bench.rb <repo-root> <label> <sizes...>
require 'json'
require 'fileutils'

ROOT  = ARGV[0] or abort 'usage: bench.rb <repo-root> <label> <sizes...>'
LABEL = ARGV[1] || 'run'
SIZES = (ARGV[2..] || []).map(&:to_i)
SIZES.replace([1, 4, 12]) if SIZES.empty?

HERE  = File.expand_path(__dir__)
HOME  = File.join(HERE, "home-#{LABEL}")
MODE  = ENV.fetch('BENCH_MODE', 'regex') # regex | plain
TIMEOUT = ENV.fetch('BENCH_TIMEOUT_MS', '90000')

def rune(*args, home:)
  out = IO.popen({ 'RUNE_HOME' => home }, ['ruby', '-I', File.join(ROOT, 'lib'),
                                           File.join(ROOT, 'bin', 'rune'), *args, '--json'],
                 err: %i[child out], &:read)
  JSON.parse(out) rescue { 'status' => 'unparseable', 'raw' => out[0, 400] }
end

FileUtils.rm_rf(HOME)
FileUtils.mkdir_p(HOME)

rows = []
SIZES.each do |mb|
  name = "bench#{mb}"
  start = rune('session', 'start', "--name=#{name}", '--',
               'ruby', File.join(HERE, 'blaster.rb'), home: HOME)
  abort "start failed: #{start.inspect}" unless start['status'] == 'ok'

  # Let the child get to its first read before the measured turn.
  sleep 0.4

  flags = ["--timeout-ms=#{TIMEOUT}"]
  flags << '--wait-for-regex=RUNE-TURN-COMPLETE' if MODE == 'regex'

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  reply = rune('session', 'send', "--name=#{name}", *flags, "emit #{mb}", home: HOME)
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

  data = reply['data'] || {}
  rows << {
    mb: mb,
    mode: MODE,
    wall: wall.round(2),
    settled: data['settled'],
    matched: data['matched'] || false,
    timed_out: data['timed_out'] || false,
    regex_timed_out: data['regex_timed_out'] || false,
    read_mb: ((data['output'] || '').bytesize / (1024.0 * 1024)).round(2),
    marker: (data['output'] || '').include?('RUNE-TURN-COMPLETE'),
    error: reply['error'] && reply['error']['message']
  }
  warn rows.last.inspect

  rune('session', 'stop', "--name=#{name}", home: HOME)
  rune('session', 'archive', "--name=#{name}", home: HOME)
end

puts JSON.pretty_generate(rows)
File.write(File.join(HERE, "result-#{LABEL}-#{MODE}.json"), JSON.pretty_generate(rows))
