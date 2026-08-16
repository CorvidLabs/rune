# Do the new guards actually catch the mistakes they are written against?
# One mutant per process, so nothing leaks between them.
#
#   ruby -I<repo>/lib mutants.rb [none|slice|abandon|firstonly]
require 'rune/session/pending_send'

PS = Rune::Session::PendingSend

case ARGV[0]
when 'slice'
  # Resume the scan by slicing rather than by position, which is exactly what
  # lets `\A` match wherever the window happens to begin.
  PS.class_eval do
    def regex_matched?
      return false unless @regex

      text = matchable
      from = scan_start
      !@regex.match(from.zero? ? text : text[from..].to_s).nil?
    end
  end
when 'abandon'
  # Abandon the echo search when the grace window closes, rather than only
  # starting to offer what has arrived.
  PS.class_eval do
    def sift(text, now:)
      @pending_echo << text
      ends_at = search_for_echo(text)
      return fix_boundary(@pending_echo[ends_at..].to_s) if ends_at
      return unless @pending_echo.bytesize > PS::ECHO_SEARCH_LIMIT || !within_echo_grace?(now)

      fix_boundary(@pending_echo)
    end
  end
when 'firstonly'
  # Drop the last-match candidate, keeping only the earliest.
  PS.class_eval { def last_match(_text, _first) = nil }
when 'nobound'
  # Never trim the window: the pre-fix semantics, kept unbounded.
  PS.class_eval { def trim_window = nil }
end

def waiting(regex, echo: 'go', settle_ms: 30_000)
  PS.new(client: nil, cursor: 0, echo: echo, now: 0, settle_ms: settle_ms,
         timeout_ms: 30_000, regex: PS.compile_regex(regex))
end

def feed(send, *arrivals, now: 1.0)
  arrivals.each do |text|
    send.absorb(text, now: now)
    out = send.outcome(now: now, child_finished: false, submitted: true, last_output_at: now)
    return out if out
  end
  nil
end

FILLER = "#{'y' * 4095}\n"

def anchored
  send = waiting('\Ayyy')
  chunks = ((PS::MATCH_WINDOW_BYTES + PS::MATCH_WINDOW_SLACK) / 4096) + 20
  feed(send, "go\n", *Array.new(chunks) { FILLER })
end

def late_echo
  send = waiting('NOTHINGMATCHES', echo: 'please ANSWER now', settle_ms: 800)
  send.absorb('', now: 0.8)
  send.absorb("please ANSWER now\n", now: 1.6)
  send.matchable
end

def repainted
  echo = 'handle the BOXDONE case'
  frame = "\e[H\e[2J\e[1;36magent\e[0m\n  \e[35m>\e[0m #{echo}\n\e[90m+------+\e[0m"
  answered = "#{frame * 12}#{frame}\n  reply: BOXDONE\n"
  [feed(waiting('BOXDONE', echo: echo), frame * 12),
   feed(waiting('BOXDONE', echo: echo), answered)]
end

def long_span
  send = waiting('BEGIN[\s\S]*END')
  chunks = (PS::MATCH_SPAN / 4096) + 4
  feed(send, "go\n", "BEGIN\n", *Array.new(chunks) { FILLER })
  feed(send, "END\n")
end

puts({ mutant: ARGV[0] || 'none',
       anchored_wants_nil: anchored,
       late_echo_wants_newline: late_echo,
       repainted_wants_nil_then_matched: repainted,
       long_span_wants_nil: long_span }.inspect)
