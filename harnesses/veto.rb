# Why does a pattern that only appears inside a repainted copy of the input
# still match? Feed the frames one at a time and see which tick accepts.
require 'rune/session/pending_send'

ECHO = 'think about REPAINTTOKEN for emit 4'
FRAME_HEAD = "\e[H\e[1;36magent\e[0m\r\n  \e[35m>\e[0m #{ECHO}\r\n"
FILLER = (("%-79s" % 'x') + "\n") * 64

def send_with(regex)
  Rune::Session::PendingSend.new(client: nil, cursor: 0, echo: ECHO, now: 0.0, settle_ms: 800,
                                 timeout_ms: 60_000,
                                 regex: Rune::Session::PendingSend.compile_regex(regex))
end

def feed(send, chunks)
  chunks.each_with_index do |chunk, index|
    now = 1.0 + (index * 0.01)
    send.absorb(chunk, now: now)
    out = send.outcome(now: now, child_finished: false, submitted: true, last_output_at: now)
    return [index, chunk[0, 60].inspect, out] if out
  end
  nil
end

# Whole frames arrive at once: the trailing half of the repaint is present.
whole = ["#{ECHO}\r\n", FRAME_HEAD + FILLER, FRAME_HEAD + FILLER]
puts "whole frames:   #{feed(send_with('REPAINTTOKEN'), whole).inspect}"

# The frame is split right after the token, which is what a 4KB pty read does
# to a frame: the copy of the input that would cover the match is only half
# there when the match is first seen.
split_at = FRAME_HEAD.index('REPAINTTOKEN') + 'REPAINTTOKEN'.length
torn = ["#{ECHO}\r\n", FRAME_HEAD[0, split_at], FRAME_HEAD[split_at..] + FILLER]
puts "torn mid-frame: #{feed(send_with('REPAINTTOKEN'), torn).inspect}"
