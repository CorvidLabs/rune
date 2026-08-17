# Several turns on one session, alternating sizes and modes, so the per-send
# state that is now carried between ticks (the fresh buffer, the match window,
# the echo boundary) has to be right at every turn boundary and not just the
# first.
require 'json'
require 'fileutils'

ROOT = ARGV[0]
HERE = File.expand_path(__dir__)
HOME = File.join(HERE, 'home-multi')

def rune(*args)
  out = IO.popen({ 'RUNE_HOME' => HOME }, ['ruby', '-I', File.join(ROOT, 'lib'),
                                           File.join(ROOT, 'bin', 'rune'), *args, '--json'],
                 err: %i[child out], &:read)
  JSON.parse(out)
rescue StandardError
  { 'status' => 'bad' }
end

FileUtils.rm_rf(HOME)
FileUtils.mkdir_p(HOME)
rune('session', 'start', '--name=multi', '--', 'ruby', File.join(HERE, 'blaster.rb'))
sleep 0.5

ok = true
[[1, true], [3, true], [1, false], [6, true], [2, false], [4, true]].each_with_index do |(mb, use_regex), turn|
  flags = ['--timeout-ms=60000']
  flags << '--wait-for-regex=RUNE-TURN-COMPLETE' if use_regex
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  reply = rune('session', 'send', '--name=multi', *flags, "emit #{mb}")
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  data = reply['data'] || {}
  got = (data['output'] || '')
  row = { turn: turn, mb: mb, regex: use_regex, wall: wall.round(2),
          settled: data['settled'], matched: data['matched'] || false,
          # Each turn's reply must hold exactly its own output: one marker, and
          # roughly the megabytes this turn asked for.
          markers: got.scan('RUNE-TURN-COMPLETE').length,
          mb_read: (got.bytesize / (1024.0 * 1024)).round(2) }
  ok &&= data['settled'] && row[:markers] == 1 && (row[:mb_read] - mb).abs < 0.25
  puts row.inspect
end
rune('session', 'stop', '--name=multi')
rune('session', 'archive', '--name=multi')
puts(ok ? 'ALL TURNS OK' : 'SOMETHING WRONG')
