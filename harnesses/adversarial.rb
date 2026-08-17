# The cases the bounded tail match could plausibly lose. Run against any repo
# checkout so before/after can be compared on identical inputs.
#
#   ruby adversarial.rb <repo-root> <label>
require 'json'
require 'fileutils'

ROOT = ARGV[0]
LABEL = ARGV[1] || 'run'
HERE = File.expand_path(__dir__)
HOME = File.join(HERE, "home-adv-#{LABEL}")
CHILDREN = File.join(HERE, 'children.rb')

def rune(*args)
  out = IO.popen({ 'RUNE_HOME' => HOME }, ['ruby', '-I', File.join(ROOT, 'lib'),
                                           File.join(ROOT, 'bin', 'rune'), *args, '--json'],
                 err: %i[child out], &:read)
  JSON.parse(out)
rescue StandardError
  { 'status' => 'bad', 'raw' => out.to_s[0, 300] }
end

FileUtils.rm_rf(HOME)
FileUtils.mkdir_p(HOME)

def turn(name, mode, text, regex, timeout: 30_000)
  rune('session', 'start', "--name=#{name}", '--', 'ruby', CHILDREN, mode)
  sleep 0.5
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  reply = rune('session', 'send', "--name=#{name}", "--timeout-ms=#{timeout}",
               "--wait-for-regex=#{regex}", text)
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  rune('session', 'stop', "--name=#{name}")
  rune('session', 'archive', "--name=#{name}")
  data = reply['data'] || {}
  { wall: wall.round(2), settled: data['settled'], matched: data['matched'] || false,
    timed_out: data['timed_out'] || false, out_kb: ((data['output'] || '').bytesize / 1024.0).round(1) }
end

results = {}

# The pattern the caller waits for also appears in their own input, and the
# child repaints that input sixty times before answering. Must not match early,
# must match the real answer, and must not cost the session.
results[:repaint_pattern_in_echo] =
  turn('advrepaint', 'repaint', 'tell me about ANSWERTOKEN please', 'ANSWERTOKEN')

# Nothing of the input ever reaches the wire.
results[:no_echo_at_all] = turn('advnoecho', 'noecho', 'find ANSWERTOKEN', 'ANSWERTOKEN')

# Answers, then quotes the request back.
results[:quote_back] = turn('advquote', 'quoteback', 'summarise the log', 'ANSWERTOKEN')

# Marker in the first line, then 8MB of noise after it.
results[:marker_before_megabytes] = turn('advearly', 'early', 'emit 8', 'ANSWERTOKEN', timeout: 60_000)

# Anchored at the very start of the reply.
results[:anchored_at_start] = turn('advanchor', 'quoteback', 'summarise the log', '\AANSWERTOKEN')

# The echo arrives a second after the grace window closed.
results[:late_echo] = turn('advlate', 'lateecho', 'please ANSWERTOKEN now', 'ANSWERTOKEN')

# One match that has to span the filler between OPEN and CLOSE: 8KB is well
# inside the re-read span, 512KB is well outside it.
results[:span_8kb] = turn('advspan1', 'spanning', 'span 8', 'OPEN[\s\S]*CLOSE', timeout: 20_000)
results[:span_512kb] = turn('advspan2', 'spanning', 'span 512', 'OPEN[\s\S]*CLOSE', timeout: 20_000)

puts JSON.pretty_generate(results)
File.write(File.join(HERE, "adversarial-#{LABEL}.json"), JSON.pretty_generate(results))
