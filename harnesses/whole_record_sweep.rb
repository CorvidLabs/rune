# frozen_string_literal: true

# `Store#whole_record?` and `Transcript.load` must agree on every line, exactly.
#
# One feeds a rotation's head event (`total_output - kept`) and the other
# reconstructs the stream from what survives, so a line one counts and the other
# drops is a permanent, silent cursor skew. `whole_record?` decides on the line's
# last byte rather than by parsing it, because parsing the kept region was twice
# measured to cost 96MB+ per rotation — so the byte test has to be provably
# exact, not merely usually right.
#
# This tears a record at every single byte offset, in every record shape, with
# braces / quotes / escapes / newlines / the marker's own bytes buried in the
# payload, and compares the two decisions.
#
# Usage: ruby harnesses/whole_record_sweep.rb

lib = ENV.fetch('LIB', File.expand_path('../lib', __dir__))
require 'json'
require 'tmpdir'
require "#{lib}/rune/session/store"
require "#{lib}/rune/session/supervisor"
require "#{lib}/rune/session/transcript"

MARKER = Rune::Session::Supervisor::TORN_MARKER

PAYLOADS = [
  'plain output',
  'has a } close brace',
  'has a "quoted" string',
  'ends in a brace }',
  "has\na raw newline",
  "has a \\ backslash and \\\" escape",
  "carries the marker itself #{MARKER}",
  '}',
  '',
  "\e[31mred\e[0m }{",
  'unicode ✓ ✗ 日本語 }',
  "tab\tand\rcarriage"
].freeze

RECORDS = PAYLOADS.flat_map do |payload|
  [JSON.generate(event: 'output', ts: 1.5, bytes: payload.bytesize, text: payload),
   JSON.generate(event: 'truncated', ts: 1.5, dropped_bytes: payload.bytesize),
   JSON.generate(event: 'start', ts: 1.5, command: payload, pid: 42)]
end

store = Rune::Session::Store.new(home: '/nonexistent', project: 'sweep')

cases = 0
disagreements = 0
byte_only_disagreements = 0

# What `Transcript.load` does with one line, as the authority.
def parses?(line)
  !JSON.parse(line).nil?
rescue JSON::ParserError
  false
end

Dir.mktmpdir('sweep') do |dir|
  path = File.join(dir, 'probe.ndjson')

  RECORDS.each do |record|
    # Every split point of every record, each one both as the file's last line
    # (no marker, nothing after it) and as a torn fragment the marker terminated
    # with a good record following.
    (0..record.bytesize).each do |cut|
      fragment = record.byteslice(0, cut)

      # (a) fragment terminated by the marker, followed by a whole record.
      File.binwrite(path, "#{fragment}#{MARKER}#{record}\n")
      File.foreach(path) do |line|
        cases += 1
        disagreements += 1 if store.whole_record?(line) != parses?(line)
      end

      # (b) fragment as the file's very last line, with no marker at all — the
      #     session ended while a gap was still owed.
      next if fragment.empty?

      File.binwrite(path, "#{record}\n#{fragment}")
      File.foreach(path) do |line|
        cases += 1
        truth = parses?(line)
        disagreements += 1 if store.whole_record?(line) != truth
        next if line.getbyte(line.bytesize - 1) == 0x0A

        # The unterminated last line, decided on its last byte alone — the shape
        # the byte test cannot settle, and the reason `whole_record?` parses it.
        byte_only_disagreements += 1 if (line.getbyte(line.bytesize - 1) == 0x7D) != truth
      end
    end
  end
end

puts "records swept:        #{RECORDS.size} (#{PAYLOADS.size} payload shapes x 3 event types)"
puts "lines compared:       #{cases}"
puts "disagreements:        #{disagreements}"
puts "  of which the byte test alone would have got wrong on an unterminated"
puts "  last line (which is why that one is parsed): #{byte_only_disagreements}"
puts(disagreements.zero? ? 'PASS' : 'FAIL')
exit(disagreements.zero? ? 0 : 1)
