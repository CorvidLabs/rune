# How long the supervisor takes to drain N MB with NO pending send at all, so
# the settle machinery is out of the picture and only pump/append/log remain.
require 'json'
require 'fileutils'

ROOT = ARGV[0]
SIZES = (ARGV[1..] || []).map(&:to_i)
HERE = File.expand_path(__dir__)
HOME = File.join(HERE, 'home-drain')

def rune(*args, home: HOME)
  out = IO.popen({ 'RUNE_HOME' => home }, ['ruby', '-I', File.join(ROOT, 'lib'),
                                           File.join(ROOT, 'bin', 'rune'), *args, '--json'],
                 err: %i[child out], &:read)
  JSON.parse(out) rescue { 'status' => 'bad', 'raw' => out[0, 300] }
end

FileUtils.rm_rf(HOME)
FileUtils.mkdir_p(HOME)

SIZES.each do |mb|
  name = "drain#{mb}"
  rune('session', 'start', "--name=#{name}", '--', 'ruby', File.join(HERE, 'blaster.rb'))
  sleep 0.4
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rune('session', 'send', "--name=#{name}", '--no-wait', "emit #{mb}")
  last = -1
  cursor = 0
  quiet = 0
  loop do
    sleep 0.25
    status = rune('session', 'list') # cheap; cursor comes from read below
    got = rune('session', 'read', "--name=#{name}", "--since=#{cursor}", '--max-output=1')
    cursor = (got['data'] || {})['cursor'] || cursor
    if cursor == last
      quiet += 1
      break if quiet >= 3
    else
      quiet = 0
    end
    last = cursor
    break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 > 300
  end
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 - 0.75
  puts({ mb: mb, drain_seconds: wall.round(2), cursor_mb: (cursor / (1024.0 * 1024)).round(2) }.inspect)
  rune('session', 'stop', "--name=#{name}")
  rune('session', 'archive', "--name=#{name}")
end
