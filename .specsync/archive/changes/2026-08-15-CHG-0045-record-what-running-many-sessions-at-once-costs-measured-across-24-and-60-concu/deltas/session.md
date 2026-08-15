## MODIFIED

### SPEC SECTION Known Limitations

- **A single line of 1024 bytes or more is silently discarded by a cooked-mode child's terminal.**
  This is `MAX_CANON`, a tty limit rather than a rune bound: the line discipline cannot assemble a
  longer canonical line, so it drops it and the child never sees it. Measured exactly — 1023 bytes
  arrive, 1024 do not, with no error anywhere. Raw-mode children (which is most full-screen agent
  CLIs) are unaffected: 300KB arrives byte-perfect. This matters because an agent prompt easily
  exceeds 1KB and nothing reports the loss. Send such input to a cooked-mode child in chunks, or
  drive a raw-mode target.
- **On Ruby 3.0 and 3.1 a `--wait-for-regex` pattern can still wedge a session.** Per-`Regexp`
  timeouts arrived in 3.2; below that there is no way to bound a single match, so a catastrophically
  backtracking pattern blocks the supervisor's only thread with no recovery but `stop`. Ruby 3.2 and
  later also memoize most textbook cases, but that optimization is disabled for patterns using
  backreferences, which is why the bound matters even there.
- **A supervisor that dies in the instant between spawning its child and recording that child's pid
  leaves the child untracked.** `abandon` can only kill what `meta.json` names, so such a child is
  reachable by nothing. The window now contains only the metadata write and cannot be closed
  entirely, since the pid does not exist until the spawn returns. In practice the pty master closing
  delivers SIGHUP, which ends most children; one that ignores SIGHUP is leaked.
- **One session is one supervisor process, which costs about 23MB and 27 descriptors.** The
  isolation is deliberate — a wedged agent takes down its own session and nothing else — but the
  price is a Ruby interpreter per session, paid up front. Measured with idle children: 24 sessions
  held 543MB and 648 descriptors, 60 held 1361MB and 1620, flat per session and unchanged across
  rounds of sends. Sixty agents therefore cost over a gigabyte before any of them does anything.
- **`stop` signals the pids recorded in `meta.json`.** If a supervisor was SIGKILLed and the kernel
  has since recycled its pid, `stop` could signal an unrelated process. Narrow, but real.
- **Settle is a heuristic, but it is a better one than 0.4.0 claimed.** That release recorded the
  reply being the answer to the question actually asked in only 5/9 turns at 800 ms, and raised the
  default to 3000 on that basis. The measurement was wrong twice over, and both faults were in the
  harness rather than in settle: prompts over ~64 characters were never submitted to Claude Code at
  all, and grok's answers were scored missing because the probe searched the byte stream, where
  repaints had split them. Re-measured with both fixed and detection moved to the rendered screen,
  the reply was correct in **27/27 claude turns and 18/18 grok turns, at every window including
  800 ms**. The longer window bought nothing and cost up to double the latency per call, so the
  default is 800 again. A send issued while the child was still producing output is still reported
  as `busy_at_send: true`, and `--wait-for-regex` on a *completion* marker remains the deterministic
  answer — but the "previous turn's answer" failure that motivated both was an artifact, and has not
  been observed since.
  What the evidence does not cover: two agents and 45 turns, both driving TUIs whose spinner runs for
  the whole turn, which is what makes byte silence mean "finished". A callee that goes quiet mid-turn
  for longer than the window still truncates.
- **A continuously animating child never settles.** Agents whose spinner runs for the whole turn
  (grok) are the easy case — byte silence genuinely means the turn ended. A child that animates while
  *idle*, or a long-running `top`-style command, never goes quiet and the send waits out
  `--timeout-ms` instead.
- **A settled reply is a byte stream, not a rendered screen — pass `--screen` when that matters.**
  A full-screen agent's answer is interleaved with its own redraws, so a 13-character reply arrives
  inside ~12 KB of repaints with the answer split across them; searching that reply for a string the
  agent plainly displayed fails. Measured against grok over three turns, the answer was absent from
  the byte stream 3/3 times and present in the rendered screen 3/3 times, which is why `--screen`
  exists. It is opt-in rather than the default because rendering is only correct for a child that
  actually paints a screen: for a cooked-mode shell the byte stream already is the answer, and the
  transcript remains the record of what happened rather than what is displayed.
- **`start` returns when the *supervisor* is ready, not when the child is.** An agent CLI takes
  seconds to boot, and input sent before it is listening is simply lost (or echoed by the
  still-cooked tty). Callers should wait for a readiness marker — via `read`, or a first `send`
  with `--wait-for-regex` — before driving a freshly started session.
- **Full-screen TUI agents produce redraw-heavy transcripts.** Driving one generates large volumes
  of ANSI repaint output; bound reads rather than pulling a whole transcript.
- **`read --tail` is close to useless against a TUI agent, and `--max-output` is the right tool
  there.** `--tail` counts newlines, and a full-screen agent's repaint stream is mostly escape
  sequences and carriage returns with very few newlines — `--tail 6` against a real agent returned
  effectively the entire 338KB transcript. This is inherent to line-counting, not a bug in the
  bound.
- **`clean_output` strips terminal control sequences but not terminal *semantics*.** With
  `TextSanitizer` widened (see the `parsers` change log) the escape codes are gone, but a
  full-screen agent's output is still a stream of repaints: the same line reappears many times and
  cursor-positioning is simply removed rather than replayed. It is readable, not a rendered screen.
  Reconstructing an actual screen would need a terminal emulator, which is out of scope.
- **`PromptScanner` duplicates the four-line last-line rule** that `PTYRunner#prompt_detected_in?`
  also implements. The honest shared home is `Parsers::PromptDetector`; extraction is deferred
  rather than done here so this change does not also rewrite the parsers contract.
- The in-memory transcript a supervisor keeps for cursor framing grows with session length.

