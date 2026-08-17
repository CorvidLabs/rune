# frozen_string_literal: true

# Measures `Transcript#from` against an independent oracle, before and after the
# gap-aware mapping, over every shape a transcript can hold: no gap at all, a
# rotation's prefix gap, one mid-stream gap, several, and a real rotation over a
# region that already contained one.
#
# "Before" is the shipped arithmetic — `since - dropped` against a single global
# accumulator — evaluated here against the same loaded transcript, so the two
# columns differ only in the mapping. The oracle knows the absolute position of
# every retained byte because this file laid the stream out, so it never asks
# the code under test where anything is.
#
#     ruby harnesses/transcript_gaps.rb
#
# Exits non-zero if any case disagrees with the oracle.

require 'json'
require 'fileutils'
require_relative '../lib/rune/session/transcript'
require_relative '../lib/rune/session/store'
require_relative '../lib/rune/session/supervisor'

HOME = '/tmp/rune-transcript-gaps'
CHUNK = 4_000

# ---- building a stream whose layout we know exactly

# An op list is the ground truth: [:out, bytes, marker] produced and retained,
# [:gap, bytes] produced and lost. Returns the file path, the total bytes the
# child produced, and the retained segments as [absolute offset, text].
def build(name, ops)
  path = File.join(HOME, "#{name}.ndjson")
  FileUtils.mkdir_p(HOME)
  abs = 0
  segments = []
  File.open(path, 'wb') do |file|
    ops.each do |kind, bytes, marker|
      case kind
      when :out
        text = (marker || 'a') * (bytes / (marker || 'a').bytesize)
        segments << [abs, text]
        file.puts JSON.generate(event: 'output', ts: 1.5, bytes: text.bytesize, text: text)
      when :gap
        file.puts JSON.generate(event: 'truncated', ts: 1.5, dropped_bytes: bytes)
      when :torn
        # What a write that failed part-way leaves: a fragment carrying
        # `"event":"output"` and a `bytes` field that no reader can parse,
        # terminated by the marker the next successful write writes.
        record = JSON.generate(event: 'output', ts: 1.5, bytes: bytes, text: 'z' * bytes)
        file.write("#{record.byteslice(0, record.bytesize / 2)}#{Rune::Session::Supervisor::TORN_MARKER}")
      end
      abs += bytes unless kind == :torn
    end
  end
  [path, abs, segments]
end

# Everything at or after `since` that the stream still holds, taken from the
# layout rather than from anything under test. Bytes before `since` are never
# part of the answer: they have already been delivered.
def oracle(segments, since)
  segments.filter_map do |start, text|
    next if start + text.bytesize <= since

    since <= start ? text : text.byteslice(since - start, text.bytesize)
  end.join
end

# The shipped mapping, unchanged: one global accumulator, correct only while
# every dropped region is a prefix of the stream.
def before(transcript, since)
  offset = since - transcript.dropped
  return transcript.text.dup if offset.negative?

  (transcript.text.byteslice(offset..) || +'').scrub
end

def after(transcript, since) = transcript.from(since)

# Bytes in an answer that sit before the cursor that asked for them — output the
# caller has already been given, handed back as new. Both the answer and the
# oracle are suffixes of the same retained text, and the oracle is exactly the
# bytes at or after `since`, so anything longer is earlier output.
def replayed(answer, want) = [answer.bytesize - want.bytesize, 0].max

# ---- the cases

def scenarios
  [
    ['no gap at all', (1..10).map { |i| [:out, CHUNK, ('a'.ord + (i % 4)).chr] }],
    ['rotation only (prefix gap)', [[:gap, 48_000]] + (1..25).map { [:out, CHUNK, 'b'] }],
    ['one mid-stream gap',
     (1..25).map { [:out, CHUNK, 'a'] } + [[:gap, 48_000]] + (1..25).map { [:out, CHUNK, 'b'] }],
    ['several gaps',
     (1..5).map { [:out, CHUNK, 'a'] } + [[:gap, 12_000]] + (1..5).map { [:out, CHUNK, 'b'] } +
       [[:gap, 8_000]] + (1..5).map { [:out, CHUNK, 'c'] } + [[:gap, 100_000]] +
       (1..5).map { [:out, CHUNK, 'd'] }],
    ['rotation over a mid-stream gap',
     [[:gap, 48_000]] + (1..5).map { [:out, CHUNK, 'a'] } + [[:gap, 12_000]] +
       (1..5).map { [:out, CHUNK, 'b'] }]
  ]
end

# One probe per boundary: before every gap, inside it, at its end, and after.
def probes(ops)
  abs = 0
  points = [0]
  ops.each do |kind, bytes, _marker|
    if kind == :gap
      points += [abs - 1, abs, abs + (bytes / 2), abs + bytes, abs + bytes + 1]
    end
    abs += bytes unless kind == :torn
  end
  (points + [abs - 1, abs, abs / 2]).map { |point| point.clamp(0, abs) }.uniq.sort
end

# ---- report

def check(label, ops)
  path, total, segments = build(label.gsub(/\W+/, '-'), ops)
  loaded = Rune::Session::Transcript.load(path)
  rows = probes(ops).map do |since|
    want = oracle(segments, since)
    old = before(loaded, since)
    new = after(loaded, since)
    [since, want, old, new]
  end
  report(label, loaded, total, segments, rows)
end

def report(label, loaded, total, segments, rows)
  puts "\n== #{label}"
  puts format('   cursor=%<cursor>d (produced %<total>d) dropped=%<dropped>d retained=%<text>d gaps=%<gaps>s',
              cursor: loaded.cursor, total: total, dropped: loaded.dropped, text: loaded.text.bytesize,
              gaps: loaded.gaps.inspect)
  puts format('   %<since>10s  %<want>8s  %<old>17s  %<new>17s', since: 'since', want: 'oracle',
              old: 'before', new: 'after')
  failures = 0
  rows.each do |since, want, old, new|
    failures += 1 unless new == want
    puts format('   %<since>10d  %<want>8d  %<old>17s  %<new>17s', since: since, want: want.bytesize,
                old: describe(old, want), new: describe(new, want))
  end
  failures += 1 unless loaded.cursor == total
  puts '   CURSOR MISMATCH' unless loaded.cursor == total
  failures
end

def describe(answer, want)
  return "#{answer.bytesize}B ok" if answer == want

  extra = replayed(answer, want)
  "#{answer.bytesize}B #{extra.positive? ? "replay+#{extra}" : 'wrong'}"
end

# ---- a real rotation, over a region that already holds a gap and a torn write

# Drives Store#rotate_output over a transcript big enough to rotate, and checks
# the cursor the reader reconstructs against the bytes the child produced. Also
# reports what the shipped accounting — output records only, fragments counted,
# `truncated` ignored — would have made the head event, which is the skew every
# later cursor inherits.
def rotation_case(label, ops)
  store = Rune::Session::Store.new(home: HOME, project: 'harness')
  name = label.gsub(/\W+/, '')[0, 60]
  store.create(name)
  path, total, = build("rot-#{name}", ops)
  FileUtils.cp(path, store.output_path(name))

  offset = store.tail_offset(store.output_path(name))
  kept_now = store.output_bytes_from(store.output_path(name), offset)
  kept_before = legacy_output_bytes_from(store.output_path(name), offset)
  store.rotate_output(name, nil, total).close
  loaded = Rune::Session::Transcript.load(store.output_path(name))

  puts format("\n== rotation: %<label>s", label: label)
  puts format('   produced=%<total>d kept(before)=%<before>d kept(after)=%<after>d',
              total: total, before: kept_before, after: kept_now)
  # The head event is `produced - kept`, and the reader then adds the bytes it
  # can actually parse — `kept(after)` by construction — so the skew every later
  # cursor inherits is the difference between the two accountings.
  puts format('   cursor before=%<before>+d  after=%<after>+d  (0 is correct)',
              before: kept_now - kept_before, after: loaded.cursor - total)
  loaded.cursor == total ? 0 : 1
end

def legacy_output_bytes_from(path, offset)
  total = 0
  File.open(path, 'rb') do |handle|
    handle.seek(offset)
    while (line = handle.gets)
      total += line[/"bytes":(\d+)/, 1].to_i if line.include?('"event":"output"')
    end
  end
  total
end

FileUtils.rm_rf(HOME)
failures = scenarios.sum { |label, ops| check(label, ops) }

big = 9 * 1024 * 1024 / CHUNK
failures += rotation_case('healthy transcript', (1..big).map { [:out, CHUNK, 'a'] })
failures += rotation_case('gap inside the kept tail',
                          (1..big).map { [:out, CHUNK, 'a'] } + [[:gap, 400_000]] +
                          (1..400).map { [:out, CHUNK, 'b'] })
[1, 4, 10].each do |torn|
  ops = (1..big).map { [:out, CHUNK, 'a'] }
  torn.times { |i| ops << [:torn, 4_096] << [:out, CHUNK, ('b'.ord + (i % 3)).chr] }
  ops += (1..400).map { [:out, CHUNK, 'c'] }
  failures += rotation_case("#{torn} torn write(s) in the kept tail", ops)
end

# What an outage actually leaves: the first failed write tears, the rest fail
# outright, and the next write that succeeds records the whole hole. The two
# errors then pull in opposite directions and do not cancel.
failures += rotation_case('an outage in the kept tail (torn write, then the gap it opened)',
                          (1..big).map { [:out, CHUNK, 'a'] } + [[:torn, 4_096], [:gap, 20_480]] +
                          (1..400).map { [:out, CHUNK, 'b'] })

puts "\n#{failures.zero? ? 'PASS' : "FAIL (#{failures})"}"
exit(failures.zero? ? 0 : 1)
