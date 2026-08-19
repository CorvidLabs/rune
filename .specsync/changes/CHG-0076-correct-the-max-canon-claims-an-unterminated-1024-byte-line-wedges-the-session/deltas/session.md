## MODIFIED

### SPEC SECTION Known Limitations


- **An orphaned child can only be reported when its identity was recorded.** The report rests on
  matching the recorded `child_started_at` against the live process's start time. Sessions started
  before that field existed report nothing, and so does a session whose supervisor died in the
  window between recording the child's pid and recording its start time — `record_running` is
  deliberately still the first write, because a pid on disk matters more than an identity for it.
  Silence therefore means "not known to be orphaned", never "known not to be".
- **`lstart` resolves to one second.** Two processes wearing the same pid within a single second
  would be indistinguishable to the identity test. Real pid reuse cannot be that fast — the pid
  space has to wrap first, measured at 2,482 pid numbers consumed per second under a sustained spawn
  loop on the development machine, so ~40 seconds for the 99,999-pid space — but the bound is a real
  one and not a proof.
- **The report needs `ps`.** Where `ps` is missing or refuses, `process_start_times` returns nothing
  and every session reports no orphan. That is the safe direction (silence, not a false accusation),
  but it is silent about being unavailable.
- **An unterminated canonical line reaching 1024 bytes wedges the session for all subsequent
  input.** This is the tty line discipline's canonical-queue limit rather than a rune bound: a
  single 1025-byte `write()` to a bare `PTY.spawn` reproduces it exactly, so rune's split
  payload/terminator write is not the cause. The budget is 1024 bytes *including* the terminator
  rune appends, so a 1023-byte payload arrives and 1024 does not — measured 20/20 deterministic with
  the child reporting its own read sizes out of band rather than via the echo. At exactly 1024 the
  payload is accepted whole and the terminator is the rejected byte, so the line can never be
  submitted and the queue never drains.

  The failure is not confined to the offending line: every later send is discarded as well,
  indefinitely (measured to +120s), while each reply reports `status: ok`, `settled: true`,
  `state: running`, `exit_code: null`. `\x15` (VKILL) clears the queue and restores delivery;
  `\x04` neither recovers nor kills the child; `\x03` ends the session at 130. After recovery the
  discarded sends are permanently absent from the child's input, which distinguishes this from
  delayed buffering.

  The discriminating condition is the tty's `ICANON` state at the moment the bytes land, established
  by holding the child binary constant and flipping one termios flag. It is not the child's identity
  — `cat`, a `sh` read loop, a Ruby read loop and a child not yet reading all wedge identically —
  and it is not whether the child drains. Consequently a raw-mode child is **not** categorically
  safe: `bash` and `python3` are raw at their prompt but cooked while a foreground command runs, and
  a 1200-byte send in that window loses the line and silently corrupts the next command. The trigger
  is also not "one over-long send" — several sends accumulating past 1024 bytes without a terminator
  wedge the queue equally.

  No reply field distinguishes a wedging send from a healthy one, and BEL is not a usable substitute:
  it is absent when an unterminated 1024-byte payload wedges the queue, present on legitimate output
  from a child that rings the bell, and suppressed entirely when `IMAXBEL` is cleared. Complete lines
  are never silently lost — they receive backpressure and an explicit refusal. Callers must chunk
  input below 1024 bytes per line regardless of the child.
- **A `--wait-for-regex` pattern that must span more than `MATCH_SPAN` characters is never
  found.** The pattern is matched against the most recent `MATCH_WINDOW_BYTES` of post-echo output;
  anything shorter than the re-read span is always found, whatever the turn grows to, but
  `OPEN[\s\S]*CLOSE` bracketing half a megabyte matched before this bound and does not now — such a
  send runs on to `--settle-ms` or `--timeout-ms` instead. Verified end to end at both sizes: 8 KB
  between the brackets matches, 512 KB does not. Wait for a marker, and use `read` for the span
  between two of them.
- **A reused `--wait-for-regex` pattern can match a reprint of an earlier answer.** `Echo#repaint?`
  vetoes a match covered by a copy of *this send's* input. It does not veto a match that is a
  reprint of *earlier output*. Measured on current main against a child that reprints its
  scrollback, sleeps 3s, then prints `DONE N`: send 1 with `'DONE \d+'` returned in 3.56s holding
  `DONE 1`; send 2 with the same pattern returned in 0.56s holding only the reprinted `DONE 1` —
  `DONE 2` was absent. Two candidate rules were considered and not shipped: rejecting a match
  whose text existed before the send loses a second `echo DONE` to a simple child; rejecting a
  match preceded by cursor-home / erase loses a TUI that paints a reused sentinel with cursor
  motion as the real new answer. Unique-per-turn sentinels wait through the reprint. A
  destination file the child writes is the other real check. `child_busy` is a `read` field
  and only means the child is still printing — it goes false during a silent think after the
  reprint, which is the measured case. Do not trust `matched` alone against a TUI that
  repaints scrollback.
- **The repaint veto needs to see a whole copy of the input, and a pty read can tear one in half.**
  `Echo#repaint?` rejects a match that a redrawn copy of the input covers, but it looks a bounded
  distance *after* the match as well as before, and that trailing half may not have arrived yet.
  Reproduced deterministically by splitting a repaint frame immediately after the token: whole
  frames are vetoed, the torn frame is not, and a pattern that appears only inside the caller's own
  input is answered `matched: true` by it. Pre-existing and unchanged by the match-window work;
  it is why a pattern that also occurs in what you sent remains the shape to avoid. Deferring such
  a match until its trailing context arrives is not obviously safe — an answer that is the last
  thing the child ever prints has no trailing context — so this is recorded rather than patched.
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
  as `busy_at_send: true`, and `--wait-for-regex` on a *per-turn* completion marker is still the
  right escape hatch for a child that redraws its input — but a reused pattern can match a reprint
  of an earlier answer, which is a different failure from the one that motivated the 3000 ms
  default, and is recorded under Known Limitations.
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
- **`--max-output=BYTES` bounds the transcript, not the reply.** The head and tail are joined by a
  `[rune] ==== N bytes omitted by --max-output ====` line, and pulling either cut back to an escape
  sequence boundary can drop a few more bytes; neither is charged against `BYTES`, so a reply can
  exceed it by roughly the marker's length. A caller sizing a buffer should allow for that. The
  budget has never been an exact ceiling in any case — `scrub` overshoots it whenever a cut splits a
  multi-byte character.
- **`clean_output` strips terminal control sequences but not terminal *semantics*.** With
  `TextSanitizer` widened (see the `parsers` change log) the escape codes are gone, but a
  full-screen agent's output is still a stream of repaints: the same line reappears many times and
  cursor-positioning is simply removed rather than replayed. It is readable, not a rendered screen.
  Reconstructing an actual screen would need a terminal emulator, which is out of scope.
- **`PromptScanner` duplicates the four-line last-line rule** that `PTYRunner#prompt_detected_in?`
  also implements. The honest shared home is `Parsers::PromptDetector`; extraction is deferred
  rather than done here so this change does not also rewrite the parsers contract.
- The in-memory transcript a supervisor keeps for cursor framing grows with session length.

