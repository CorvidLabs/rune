# Changelog

## [v0.9.0] - 2026-08-17

### Fixed

- **A cursor issued before a gap in the middle of the transcript replayed output already
  delivered.** `Transcript#from` mapped a cursor by subtracting one global dropped total, which is
  correct only while the dropped region is a *prefix* of the stream — true for rotation, and false
  for a write that fails mid-session and leaves a hole with output on both sides of it. Every cursor
  from before such a hole resolved |hole| bytes too early. Measured on 25 chunks x 4000B, a
  48_000-byte hole and 25 more: `read --since=100000` returned 148_000 bytes starting at the
  beginning of the stream, 48_000 of which the caller already had — arriving, for an agent polling
  `read --since=<last cursor>`, as new output for the current turn, which re-fires prompt detection
  and every "did my command finish" check built on it. Each dropped region is now recorded as
  `(retained offset, cumulative dropped)` and a cursor is walked through the list; one that lands
  *inside* a region clamps forward to its end, because those bytes are gone either way and later
  output is honest where replaying earlier output is not. A single prefix — every rotation — is byte
  for byte the arithmetic it always was.

- **A transcript write that failed was survived, not recorded.** The in-memory cursor advanced over
  bytes nothing on disk accounted for, so every cursor `send` handed out was unresolvable by `read`
  for the rest of the session, and logging that resumed over the hole never mentioned it. Output no
  write could record is now carried and emitted as a `truncated` event by the next write that
  succeeds, each record is written on its own, and the first record after a failure is preceded by a
  marker that makes any fragment the failed write left unparseable — so "recorded" means exactly
  "its own write returned". While the hole is still owed, `status` and the `send` reply carry
  `transcript_gap_bytes`, the only place it is known at all.

- **Rotation counted bytes the reader does not, in both directions.** A rotation's head event is
  `total_output - kept`, so the scan of the kept region has to count exactly what `Transcript.load`
  reconstructs from it. It counted neither a `truncated` event already inside the kept tail — a hole
  then counted twice, putting every later cursor 400_000 bytes past the end of the stream in the
  measured case — nor did it exclude the fragment a torn write leaves, which still reads as an
  output record while the reader skips it: -4096/-16384/-40960 bytes of permanent, silent shortfall
  for 1/4/10 torn writes, scaling with the outage because each fragment becomes a countable line of
  its own. (That this is *worse* than 0.8.0's flat -4096, where a fragment and the record after it
  merged into one unparseable line, is carried over from the prototype's measurement and was not
  re-derived here.) A real outage moves both dials and they do not cancel: +16384 measured
  for a torn write plus the gap it opened. All of those, and a healthy transcript that must not
  move, measure 0.
- **A rotation that failed silently stopped a session recording, permanently.** `rotate_output`
  closed the caller's handle before it had a replacement to hand back, so any later failure left the
  supervisor holding a closed handle it had no idea was closed — and `log_event`'s own rescue then
  swallowed every subsequent write for the rest of the session's life, while the cursor `send` hands
  out kept advancing over a transcript that had stopped growing. Reproduced on a real EACCES session
  directory (`harnesses/rotation_eacces.rb`): 200 further events left the transcript 564,000 bytes
  behind the cursor, and restoring write permission did not resume recording, it widened the gap to
  654,000. The handle is now closed only once the replacement is renamed into place, and a
  half-written temp file is removed on the way out. With the handle surviving, `@log_bytes` stays
  over the ceiling and every further event would retry the rotation, so a failure is now backed off
  30s: one failed attempt seeks and scans the 8,388,576-byte tail it means to keep before it
  discovers it cannot write, 4.8ms each, on the single thread that also drains the pty — 189
  attempts over 200 events before the backoff, 1 after.

- **A transcript write that failed left every later cursor unresolvable, silently and for good.**
  `log_event` swallowed the error while the in-memory cursor kept advancing, so `send` handed out
  positions `read` could never resolve and nothing anywhere said so. Reproduced with RUNE_HOME on a
  full 20MB ramdisk: 852,000 bytes of output went unrecorded under `dropped: 0`, and freeing the
  disk made it worse, because logging resumed over the hole without a word. The lost byte count is
  now carried and emitted as a `truncated` event by the next write that succeeds — the same vehicle
  rotation already uses to keep cursors absolute. Re-measured on the same ramdisk: skew −873,000
  during the outage, 0 after recovery, with `dropped` reporting the hole exactly. While the hole is
  still owed there is nowhere on disk to put it, so `send` replies and `status` carry
  `transcript_gap_bytes`.

  A write that fails part-way also leaves a fragment, and a fragment can be a complete JSON object
  that merely never got its newline — which then swallows the next good record into one unparseable
  line. Measured on that ramdisk: 280 of 300 writes failed and one produced exactly that, 4,938
  bytes parsing as neither. A `|torn` marker now precedes the first record after any failure, so
  only the fragment is lost. `Store#whole_record?` decides the same question for rotation's
  accounting on a byte comparison rather than by parsing the kept region — which was twice measured
  to cost 96MB+ per rotation — and the two must agree exactly or the skew is permanent: swept over
  every split point of 36 record shapes with braces, quotes, escapes, raw newlines and the marker's
  own bytes in the payload, 8,832 lines compared, 0 disagreements.

- **Teardown recorded the child as exited while it was still running.** `Supervisor#cleanup` wrote
  `state: 'exited'` and only then terminated the child, so a supervisor dying inside that window
  left a concluded record on disk beside a live process still holding a pty. `conclude` already
  killed before recording on the normal path; the abnormal teardown now matches it. `terminate_child`
  is idempotent and each teardown step keeps its own rescue, so a child that will not die still gets
  the record written after it.

- **`rune run --timeout` never returned when the child was still printing.** The flag that exists to
  bound a run did not bound it: on macOS a pty child SIGKILLed while bytes it wrote sit unread in
  the pty buffer wedges permanently in the kernel exit path (`ps` shows `?Es`), so the blocking
  `Process.wait2` after the kill never returned. Reproduced independently against the released
  0.8.0 with a hard 40 s ceiling and rune's own output redirected to a file, so "rune has not
  exited" could not be confused with a blocked reader — the rune process itself sat in state `S`:

      rune run --timeout=3 -- sh -c '<case>'         v0.8.0      after
      child ignores TERM, prints constantly          HUNG 40s+   124 in 5.5s
      child ignores TERM, silent                     124 in 3.1s 124 in 3.2s
      child handles TERM, prints constantly          HUNG 40s+   124 in 5.5s
      child handles TERM, one burst then idle        124 in 3.2s 124 in 3.2s

  Note the second and fourth rows: ignoring TERM was never the trigger, and a child that has
  stopped printing exits cleanly. The discriminator is whether the child is *actively producing
  output at the moment of the kill*, which is why every earlier fixture missed it — a silent test
  child leaves nothing unread and never wedges. `SignalHandler.reap` is now bounded at every step
  and takes a drain block, and the abort is caught inside the read loops where the pty reader is
  still open, because reading the master is the only thing that clears the wedge. The
  `--timeout`/`--idle-timeout`/EPIPE kill paths are bounded too, but cannot drain — Ruby's internal
  timeout exception is not a `StandardError`, so it cannot be caught while the reader is open. A
  child wedged on those paths is given up on rather than waited for: strictly better than an
  unbounded wait, and a documented limitation rather than a fix.

- **A second INT/TERM to rune now stops it, instead of only being forwarded.** Signals are enqueued
  on a `Thread::Queue` and drained by the poll callable, so two arriving inside one 0.2 s poll no
  longer overwrite each other and every signal reaches the child. The second signal within a 5 s
  burst window is forwarded to the child *first*, then unwinds to a well-formed result at
  `128 + signo` rather than killing rune mid-render; the window is what keeps two legitimate
  interrupts ten minutes apart from counting as an escalation, and the traps are restored to
  `DEFAULT` afterwards so a third signal is the last escape hatch. This is the `timeout`/`docker
  run`/`ssh` ladder, and it is a deliberate trade-off: two signals to the *rune process* end the run
  even if the child would have carried on. Under `rune watch` it is moot — raw mode clears `ISIG`,
  so a human's Ctrl-C reaches the child as a `0x03` byte and never becomes a signal to rune at all,
  verified through a real controlling terminal. Agent-CLI turn-interrupts are untouched.

- **`send` accepted `--max-output` and `--tail` and silently ignored both.** They were parsed for
  every session subcommand and applied only by `read`, so a caller that asked for a bound was told
  `status: ok` and handed everything: measured against `python3 -q`, `send --max-output=120` and
  `send --tail=3` each returned the same 4187 bytes as no flag at all, while `read --max-output=120`
  correctly returned 65. `send` is the worst place for that gap — it is the call an agent makes most
  and one turn of a full-screen TUI is megabytes, which is exactly how a driving loop pages a whole
  transcript into its context believing it set a limit. `clean_output` is derived from the *bounded*
  raw text rather than bounded separately, so the two fields cannot describe different windows of
  one reply with a single `omitted_bytes` true of only one of them. Bounding stays in the command,
  not the supervisor: the transcript, the cursor, and every attached client still see the whole
  stream. Separately, `--max-output` together with `--tail` is now refused on every session
  subcommand with the message `rune run` has always used — accepting both applied whichever was
  tested first and silently gave the caller the other one.

### Added

- **Subcommands are structured data in per-command help.** `rune --help --json` answered with
  `commands: [{name, summary}, …]` while `rune session --help --json` had no `commands` key at all:
  its seven subcommands appeared only inside the `usage` line as `<start|send|read|…>`. Discovering
  the CLI therefore worked structurally for exactly one level and then required splitting a
  display string, which a field report hit while driving real agent CLIs. Per-command help now
  carries the same key and the same entry shape as the top-level list, so one parser reads both
  levels. A command with no subcommands emits no `commands` key, leaving every existing payload
  unchanged. The declared list and the dispatch table are separate on purpose — declaring carries
  the summaries — so the suite asserts they are equal, since a subcommand that dispatches without
  being declared would otherwise work on the command line while being invisible to discovery.

- **`orphaned_child_pid` on `list` and on the `archive` reply.** A supervisor killed with SIGKILL
  leaves its child running, reparented to pid 1 and still holding the pty, and nothing said so:
  `list` showed the session `dead` and `archive` filed it away, after which no rune command could
  name the process at all. Both now report the pid when a session's supervisor is gone and its
  recorded child is provably still running. Nothing is blocked and nothing is signalled — the
  operator is told the number while it is still reachable.

  "Provably" is the pair (pid, start time), recorded by the supervisor at spawn and compared against
  the live process, under `LC_ALL=C` because `lstart` is formatted through the locale
  (`Fri Aug 14 13:41:13 2026` under C, `ven. 14 août 13:41:13 2026` under fr_FR). It is deliberately
  not the bare pid, which any recycled number satisfies, and deliberately not the process *group*:
  measured on the development machine, 1,222 of 1,390 live processes (87.9%) lead their own group
  and 130 of the 200 most recently allocated pids (65.0%), so a group question answers "alive" for a
  stranger about as often as a bare pid does — and misses a real child that is not a group leader.
  The recorded `state` is not consulted either, because a check that skipped sessions recorded
  `exited`/`stopped`/`failed` would be blind to exactly the teardown bug fixed above.

  Where the question cannot be asked soundly the answer is silence: a session with no recorded
  `child_started_at` reports nothing even when its child is alive, and so does every session if `ps`
  is unavailable. `lstart` resolves to one second, so two processes wearing one pid inside a single
  second are indistinguishable — the pid space has to wrap first, measured at ~40s of sustained
  spawning here, but that is a bound and not a proof. `harnesses/orphan_report.rb` drives all of it
  against a real SIGKILLed supervisor.

- **`--max-output` returned text the child never printed.** The head and tail were spliced with
  nothing between them, so the join reads as continuous output. Measured, a 201-byte transcript at
  `--max-output=200` dropped exactly the byte that turned `chsh -s /bin/zsh` into
  `chsh -s bin/zsh` — a different and still-plausible path — under `status: ok`. The metadata was
  honest throughout; the text was a fabrication, and a caller reading only `clean_output` had no
  in-band signal at all. The join now carries a
  `[rune] ==== N bytes omitted by --max-output ====` line. It is rune's annotation rather than the
  child's output, so it is not charged against BYTES and a reply can exceed the budget by its
  length — which is not a new kind of overshoot: `scrub` has returned 62 bytes for a budget of 60
  since the flag shipped, whenever both cuts split a multi-byte character. `truncated` and
  `omitted_bytes` stay authoritative, because a child can print any string, this one included.

- **Both `--max-output` cut boundaries could land inside an escape sequence.** A head that kept an
  OSC introducer and lost its terminator makes `strip_ansi` swallow the marker *and* the start of
  the tail; a tail that begins mid-CSI prints its remainder as text. Both are now pulled to a
  sequence boundary — the head back to the ESC that opened the one it split, the tail forward past
  that sequence's final byte — and the bytes that costs are counted in `omitted_bytes`. Censused
  over all 14,029 cut points of a real vim transcript: 2,306 head cuts and 4,399 tail cuts fell
  inside a sequence and every one emitted the orphaned remainder; now none do, and the marker
  survives `strip_ansi` at all 14,029 (previously 0). Confirmed on two independent oracles: GNU
  screen and pyte both display `A31mBBB` for the remainder of a sliced `\e[1;31m`, and both
  swallow everything after an OSC introducer that never terminates.

- **An unparseable `--grep` returned the entire transcript under `status: ok`.** The exact opposite
  of the same read with a valid pattern that matches nothing, which returns zero — so a caller that
  did not read `grep_error` saw every line as though it had matched, at the maximum possible cost.
  A filter that cannot run now fails closed: no output, `grep_matches` absent rather than `0`
  (nothing was searched), and `grep_error` carrying Ruby's own reason instead of just echoing the
  pattern. The read itself still succeeds, because `cursor`, `dropped_bytes`, `prompt_detected`,
  `idle_ms`/`child_busy` and `screen` have no bearing on the pattern, and human mode now prints the
  reason above what would otherwise be a bare blank line.

- **A mistyped flag was typed at the child, or exec'd as a program.**
  `session send --name=x --settle_ms 500 'echo HELLO'` (underscore for dash) matched nothing, so
  the flag, its value and the input were joined with spaces and written to the child, answering
  `status: ok`; against an agent CLI that is a garbage prompt to a paid model. `rune run
  --tiemout=5 -- echo hi` gave `status: ok` with `exit_code: 127` and
  `Command not found: --tiemout\=5 -- echo hi`. Both now refuse a flag-shaped token that matches no
  rune flag, with a dash-for-underscore suggestion where one applies exactly. Two limits keep the
  refusal from catching anything that works today: nothing after the first `--` is examined, and
  nothing after the first operand is examined — so `session start --name=x claude --resume`,
  `run cargo clippy --tests`, `send --name=x -- --settle_ms` and `--- section ---` are all
  untouched.
- **`--screen` rendered at a hardcoded 40x120 while the child ran at whatever size a human's
  terminal was.** `attach` resizes the child to the terminal that took it over and follows it as
  that terminal is resized, so for the entire time anyone was attached from a window that was not
  40 rows tall, rune's distinguishing output described a screen the child never drew. The supervisor
  now records the child's winsize in `meta.json` whenever it changes it, and both `read --screen`
  and `send --screen` render at it and report it as `screen_rows`/`screen_cols`.

  Measured end to end against a child that lays its output out against its winsize three ways at
  once, with pyte 0.8.2 and GNU screen 4.00.03 replaying the same bytes as independent oracles that
  agreed with each other exactly. Driven over the control socket: **36/37 rows wrong before and 0/31
  after** at 30x100, 30/31 → 0/25 at 24x80, 18/19 → 0/13 at 12x40, 50/51 → 0/51 at 50x200, and 0/41
  both ways at 40x120 where the sizes coincide. Driven through a real `rune session attach` in a
  real 30x100 pty, against the bytes that terminal itself received: **29/30 before, 0/30 after** —
  and that with a child that ignores SIGWINCH entirely, because the supervisor replays its backlog
  into the attaching terminal at that terminal's size.

  **`screen_size_recorded` is what tells a recorded size from the fallback.** The numbers cannot: a
  session attached from a 40-row terminal records exactly the fallback's 40x120. It is false for a
  session nobody has resized (where 40x120 is not a guess — it is the size the supervisor gave the
  pty), for a session directory predating this, and for a recorded size that is not a usable
  terminal, which is discarded or clamped rather than allocated.

  A resize arriving over the control socket is clamped to 300x1000, past any real terminal, and the
  clamp lands on the pty as well as on the record so the child, the record and the render always
  agree. A pty's winsize fields are 16-bit, and a recorded 65535x65535 would have made every later
  `--screen` drive a grid that size for the rest of the session's life — the denial of service
  v0.8.0 clamped inside the renderer, reappearing one layer up with the amplification persisted to
  disk. One `read --screen` over a hostile 683KB `\e[999L` transcript: 0.76s at 40x120, 3.41s at the
  ceiling, 17.72s without it.

  **One case is documented rather than fixed.** The whole retained transcript is rendered at the
  child's *current* size, so output painted before a resize is re-flowed at the new one. For a
  full-screen agent that is right, and for an attaching terminal it is exactly right (the 0/30 above
  is that case). It is unresolved for a child that never repaints *and* whose pty is resized under
  an already-attached terminal, where that terminal reflows glyphs it has already drawn and there is
  no reference answer to match: shrunk from 40x120 to 24x80 mid-stream, GNU screen kept only the
  cursor row, pyte kept nothing, and the two disagreed with each other on one row of what remained.
  rune keeps the content and re-flows it, differing from both; the old fixed size scored better
  there on raw row counts (15 wrong against 24) only because a mostly blank screen coincidentally
  matches a mostly blank oracle.

- **`meta.json` was truncated in place while other processes were reading it.** Every rune process
  answers "does this session exist, and is it alive?" out of that file with no lock to take, so an
  instant where it was short was an instant where `send` said "No such session", `list` reported
  `state: dead`, and `read --screen` fell back to the default geometry. Rare while meta was written
  a handful of times per session; not rare once the child's winsize is recorded there, because a
  human dragging a window edge emits a SIGWINCH per frame. It is now serialised first, written whole
  to a private per-pid temp file, and renamed over the target, the same shape transcript rotation
  already used. Measured through a real `rune session attach` dragged across 250 window shapes in
  7.5 seconds, with another process doing exactly what `alive_session` does: **90 of 294,728 reads
  came back unreadable before, 0 of 312,582 after**. Amplified by padding meta and rewriting it 200
  times against a concurrent reader: 303 unreadable reads before, 0 after.

### Verified, not changed

Two durability claims had been specified and unit-tested but never observed end to end. Both were
run against a live session for this release, and neither needed a change — recorded because "we
believe it holds" and "we watched it hold" are different statements.

- **A transcript rotation, observed.** A field report noted "no rotation observed" over ~50 minutes,
  which is the one thing a reporter cannot manufacture on demand. Driving 41.7 MB through a single
  `python3 -q` session crosses `MAX_LOG_BYTES` (32 MB): the rotation fired between 20 and 30 MB,
  dropped 22,843,377 bytes, and left the transcript at 9.2 MB and growing. The cursor stayed
  monotonic across it (1,604 → 41,695,634 → 41,697,712), a `read --since=<pre-rotation cursor>`
  still answered and reported `dropped_bytes: 22843377` rather than silently renumbering, and the
  session took further sends afterwards. This is the path CHG-0057's cursor-gap arithmetic exists
  for, exercised by a real rotation rather than a synthesised one.

- **A stalled attach client cannot wedge the supervisor.** The event loop is single-threaded and
  `attach` is a push stream, so a client that attaches and stops reading is the shape most likely to
  stall the loop that also drains the pty. Non-blocking writes were built for this in 0.7.0; the
  guarantee had not been watched under load. With three clients attached and one deliberately never
  reading again, 4.1 MB was driven through the session: the control plane kept answering `status`,
  `read` kept working, a healthy attacher kept receiving, backlog replay had reached all three
  identically (1,990 bytes each), and the supervisor survived every client disconnecting at once.

## [v0.8.0] - 2026-08-16

Four independent agents reviewed rune before this release, each on a different lens: renderer
correctness against two reference emulators, supervisor races and lifecycle, every factual claim in
the docs executed rather than read, and a session spent driving real multi-step work through it.
They found nine real bugs and a page of documentation that was wrong rather than merely missing.
That method is now recorded in `ROADMAP.md` as a prerequisite for 1.0, because it keeps working:
most of the sharpest bugs in this project were found by an agent other than the one that wrote the
code.

### Fixed

- **`--wait-for-regex` matched the pty's echo of your own input.** It fired on
  `send "…print DONE" --wait-for-regex DONE`, the primary way to drive an agent. The echo was
  located by exact substring, which fails whenever the child *transforms* it — a REPL repainting per
  keystroke, readline wrapping past the terminal width. It is now located in **condensed** text,
  escapes and whitespace removed from both sides, with the offset memoised and a veto rejecting a
  match that a repainted copy of the input covers. Measured against `python3 -q`: previously it
  returned in 0.22s with `matched: true`, eight seconds before the code ran, 4 times out of 4; it
  now waits for the real output, 3 times out of 3.

  Worth recording what was rejected, because the roadmap had named it as the likely fix: rendering
  the stream with `ScreenRenderer` and locating the echo on the rendered screen scored **worse** than
  the shipped baseline and was the most expensive option tried. It fails on the wrap case precisely
  because a slice starting mid-screen has no way to know the cursor column.

- **`send` could settle on the pty's echo of your own input and return your words as the answer.**
  The exact thing the guide promised would not happen. `observe` passed `now: nil`, and the
  partial-echo guard reads `if now && ...`, so a nil clock skipped it and a half-arrived echo
  counted as a reply — and since that flag latches, one such tick was enough. A pty delivers a long
  line in several reads, so this fired for any input longer than one read, which is most real
  prompts. Measured against `bash -i` with a three-second command: **0 of 3 runs returned the
  answer before, 3 of 3 after** — including inputs that wrap past the terminal width. It does **not**
  cover a child that *redraws* the input: `irb` and `python3 -q` still settle on their own repaint,
  which is now documented in the guide and is the top item on the road to 1.0.
- **A single escape sequence in child output could crash, hang, or exhaust memory.** Counts were
  used unclamped as loop and allocation bounds, so `\e[99999999999999999999@` raised `RangeError`
  out of `.render` and killed `read --screen`, `\e[999999999@` allocated 2.9GB, and `\e[1000000L`
  never returned. Seven such cases now complete in 0.000s. This renders untrusted bytes, so an
  unclamped count was a denial of service rather than a cosmetic bug.
- **Scroll regions were ignored, which was the whole real-world rendering error.** `\e[t;br` was
  dropped, so a line feed at a region's bottom walked down the page instead of scrolling inside it —
  and every pager, editor and full-screen agent sets a region. Replaying two captured agent
  transcripts against a reference emulator, **8 of 40 rows differed; stripping only the region
  sequences from the same bytes dropped that to 0.**
- **Sequences the parser did not recognise were printed onto the screen.** Three separate causes,
  one symptom, and the same failure as the `ESC D` that once printed a literal `D`: the CSI pattern
  was not the ECMA-48 grammar, so `\e[2 q` (emitted by fish, starship and Codex CLI) and the colon
  form of truecolour SGR fell through; eight escapes including `RIS` and the charset designators had
  no handler; and a sequence the stream ended in the middle of printed its body, which for a live
  session is the normal case rather than an edge one.
- **`\e[3J` and undefined erase parameters wiped the screen.** Both erase families used `else` as
  "erase everything", so `\e[9K` destroyed a line and `\e[3J` — "erase *saved* lines", which this
  renderer does not keep — cleared output that was still on screen.
- **Resolving a large turn was quadratic in its size.** `beyond_echo` re-scanned the whole
  accumulated slice every tick even after the answer had been recognised. A 12MB burst the child
  produced in 3s took the supervisor 67s at 100% CPU, and a caller with a 30s timeout was told it
  timed out while holding two thirds of a completed answer.
- **`--context 3` was silently ignored.** The separate form of the flag, which is the form the guide
  shows. `--context=3` worked. The alias table was missing an entry, which also made errors name
  flags that do not exist: `Invalid --tail-lines value`.

### Documentation

Every factual claim in the docs was executed rather than read. Fifteen were wrong; the ones a caller
would have built on:

- **`child_busy` and `idle_ms` were listed as fields of a `send` reply.** They are on `read` and
  `list`. A caller following the guide got `nil` and fell back to grepping the callee's UI, which is
  precisely what those fields exist to replace.
- **The `rune run --help --json` example was three flags stale**, in the one place `--max-output`,
  `--tail` and `--separate-streams` could have been documented — and it was offered as proof that an
  agent can discover the surface without scraping text. Both copies are now generated from real
  output, and `--separate-streams` documents its real cost: it gives stderr its own pipe, so the
  child no longer sees one controlling terminal.
- **The architecture guide described the *old* `prompt_detected` semantics**, replaced deliberately
  in 0.3.0, and listed two prompt signatures that are not detected. The claims were removed rather
  than the patterns added: the detector's conservatism is deliberate.
- The README's test numbers (`179 examples, 98%+`) against an actual 405 and 87%, an install command
  that is not a valid `fledge plugins install` source, `session start` examples matching neither
  output mode, and the `MAX_CANON` guidance, which claimed a shell-like child never sees a long line
  — `bash --norc -i` uses readline, so it takes a 1995-character line byte-perfect.

Newly documented because testing found them undocumented: `--no-wait` returns a different shape,
`--no-newline`, that archiving puts a session out of `read`'s reach, and that **`start` returns
`status: "ok"` and exits 0 when the command does not exist** — with `state: "exited"` and
`exit_code: 127` in the body, so a caller checking the process status believes it started.

`ROADMAP.md` was three releases out of date, still tracking 0.2.0. It now records where rune is,
what 1.0 needs, and every finding from this round that is not yet fixed.

### Changed

- **The provenance gate is off**, and `.trust.toml` records `provenance.mode = "off"` with the
  reason rather than leaving a check to keep failing. It required signing every commit by hand
  before a release; that step was skipped for v0.4.0, v0.5.0 and v0.6.0 and nobody noticed for three
  releases, because the only thing gated on it was a GitHub Packages gem that nothing installs — the
  Homebrew formula builds from the tag tarball and the rubygems.org job is disabled. Moving the same
  check earlier, into the release lane, only converted a silent failure into a blocked release: the
  gate was either skipped without consequence or stopped the work, and never in between. The
  tag-and-version validation that actually prevents a wrong release is untouched.

### Known and not fixed

- **The settle path can still return your own input as the answer when the child redraws it.**
  `--wait-for-regex` is fixed; `--settle-ms` is not. A rule was prototyped, measured at 12/12 on the
  failing cases, and **rejected** because it broke a child whose reply ends with the request — the
  counterexample and why coverage-based rules cannot work either are recorded in `ROADMAP.md`, so
  the next attempt starts past that dead end.
- Seven further findings are listed in `ROADMAP.md`, including `--max-output` splicing head and tail
  with no marker, an unparseable `--grep` returning the whole transcript, and unknown flags being
  typed at the child rather than rejected.

- **The screen tail could cut an escape sequence in half and print its remainder onto the screen.**
  Found from a census of a real agent's output: 109,364 absolute cursor moves and 31,798
  synchronised-update brackets across 4.5MB, and **zero** erases of any kind. A stream that is
  almost entirely escape sequences makes the render window's cut far likelier to land inside one
  than in text, and the remainder has no `ESC` left to identify it — cutting inside `\e[?2026h` put
  a literal `?2026h` on screen. The code carried a comment claiming this was harmless. The cut now
  resyncs to the first escape, bounded so that a stream with no escapes keeps its text.
- **Three releases in a row failed to publish and nobody noticed.** v0.4.0, v0.5.0 and v0.6.0 each
  failed at the provenance check inside `Publish Gem Package` — after the tag existed and the
  release was announced — because the documented step that records provenance was skipped. Nothing
  downstream broke, which is exactly why it went unseen: the Homebrew formula builds from the tag
  tarball and the rubygems.org job is disabled, so the only casualty was a package nobody installs.
  The release lane now runs `provenance-check` up front, so a missing attestation stops a release
  before the tag rather than after it, and says what to run to fix it.

## [v0.7.0] - 2026-08-15

Everything here comes from one day of field use: an agent drove grok through rune to do real work on
another repository — eight one-shot dispatches and a live session — and reported back with
measurements rather than opinions. Two of its five findings turned out to be right about the symptom
and wrong about the cause, which is why one of them appears below as a documentation fix rather than
a code change, and why the most important one is deliberately still open.

### Added

- **`read --grep=RE --context=N`.** Finding one line in a 379KB transcript otherwise means pulling
  most of it into the caller's context, and neither `--since` nor `--tail` helps when what you want
  is in the middle. It matches the **cleaned** text rather than the raw stream, because a
  full-screen agent's repaint frames split words across escape sequences — a pattern plainly visible
  on screen does not match the bytes, which would make the feature look broken exactly where it is
  needed. `grep_matches` comes back in the reply; an unparseable pattern returns `grep_error`
  instead of raising, since a caller's typo is not a reason to fail a read.
- **`child_busy` and `idle_ms` on `read`.** The reporter had no structured way to ask whether the
  child was still working, so was grepping the callee's own rendered UI for `command still running`.
  That is presentation, not API, and it breaks the first time the wording changes. Both fields are
  derived from the transcript's own event timestamps rather than asked of the supervisor — the same
  source `list` already uses, so they work identically once a session has stopped. Measured:
  `child_busy=true, idle_ms=61` while printing; `child_busy=false, idle_ms=3268` after finishing.
  The field is named for what it observes, and the case it cannot see — a child that backgrounds a
  command and goes quiet reports `child_busy: false` while still working — is stated next to it
  rather than left to be discovered.

### Documentation

- **`prompt_detected` was described as usually false for agent CLIs.** It is not, and a caller had
  already built on the claim, which is worse than no documentation at all. Measured: `plain output`
  false, `$ ` false, `Do you want to proceed? ` **false**, `❯ ` **true**. So the report of "true 8
  times out of 8" was correct for that callee, and the conclusion that the field discriminates
  nothing was not — it discriminates, but answers "does the last line look like a prompt", and
  answers it backwards for the permission dialog, which is the case worth catching. Documented with
  that table.
- **`settled` has three causes of quiet, not two.** The turn finished, the child is waiting on a
  human, or the child backgrounded a long command and stopped printing. The third was missing and it
  is the one that produced a false "finished" 260 seconds early in real use. The rule is now stated:
  if you are deciding on the *absence* of something, `settled` is not sufficient evidence.
- **`exit_code` answers whether the process ended, not whether the work succeeded.** All eight
  one-shot dispatches returned 0, including runs whose conclusions the caller later had to correct.
  The field was behaving correctly and the documentation never said what it meant. Renaming it would
  convey the same information at the cost of breaking every existing caller.

### Not fixed, deliberately

- **Polling `--screen` can return a half-painted frame.** The most important finding in the report,
  and it ships unaddressed. Two hypotheses were tested and discarded: comparing consecutive renders
  measured *worse* than the status quo — 13 torn frames out of 20 against 11 — because a cyclic
  painter rarely renders the same frame twice, so it times out and returns the torn frame anyway;
  and the renderer's tail window cannot drop a screen clear, because a cut that removes the clear
  removes everything before it too. Redefining it on quiescence could not reproduce the tear at all,
  the identical child giving 11/20 once and 0/20 twice, which means the harness is not measuring
  what it appears to. A fix that fails silently toward "looks done" would be worse than a documented
  limitation. A reproducer has been requested.

### Internal

- `Session::Transcript` extracted from `SessionCommand`, which had reached 930 lines with a third of
  it on one subject: reading the durable NDJSON log, cursor arithmetic across rotation, search and
  screen rendering. Keeping the dropped-byte count on the object rather than threading it through
  every call is what makes the cursor arithmetic hard to get wrong — four methods each took it as an
  argument and each had to remember what it meant. No behaviour change; `session_command.rb` 930 →
  853.

## [v0.6.0] - 2026-08-15

A fix release. Everything here was found by *running* rune — driving real agent CLIs and watching
processes over time — rather than by reading it. Two of the bugs were in code added earlier in the
same week, and one was reported from real use.

### Fixed

- **A session's memory and disk both grew without bound, for as long as the session ran.** A
  persistent session is the whole feature, so this mattered most where it was least visible.
  Resident memory tracked output one-for-one — 27MB to 69MB in eighty seconds at 500KB/s — because
  the supervisor held every byte the child had ever produced. It now keeps a bounded window and
  memory plateaus: over one 150-second run the last 60 seconds added 30MB of output and 0.16MB of
  memory. The transcript **file** had the same problem and was worse, since memory is reclaimed when
  a supervisor exits and a file is not: nothing pruned it, and `archive` moved it rather than
  removing it, so a 150-second run left 80MB behind permanently. It now rotates, keeping the recent
  tail. Cursors are unaffected — a `truncated` event records what was dropped, so a cursor still
  names the same position in the stream and `read` reports `dropped_bytes` rather than quietly
  returning less than was asked for.
- **Rotation itself then cost more memory than the growth it prevented.** Caught by running two
  sessions in conversation for 45 minutes and 4176 turns: memory sat at 145MB until the first
  rotation and jumped to 374MB the instant it ran. Rotation now seeks to the cut point rather than
  scanning what it drops, reads the byte count each event already records instead of parsing the
  event, and copies with `IO.copy_stream`. One rotation went from **+229MB to +0.1MB**. Worth
  recording that the obvious fix — streaming the lines but still parsing them — still cost 96MB and
  would have shipped had it not been measured again.
- **An attachment reported both that the session was still running and that it had ended, in the
  same exit.** Reported from real use against a grok session. The note fired whenever an attachment
  had been established rather than only when the human actually detached. A deliberate detach now
  says so and exits 0; an attachment that ended because output stopped says that instead, exits 1,
  and points at `rune session list` rather than asserting a cause it cannot know.
- **Six defects found by a read-only council review** of 0.5.0 — grok on the renderer, kimi on the
  send path, agy on teardown, one lens each. The renderer printed the byte after any escape it did
  not recognise, so `ESC D` rendered a literal `D`; it discarded cursor save/restore under a comment
  claiming the ignored sequences could not move the cursor; and it left the last-column cursor in a
  state no terminal uses, so backspace, `CUB`, line feed and `EL` all read it wrong. `VPA`, the
  insert/delete/erase-character family and line insert/delete/scroll are now implemented, and
  vertical tab and form feed are motion rather than text. On the send path, an outstanding terminator
  could be appended to still-queued text, putting both in one read — the exact coalescing the
  terminator delay exists to prevent — and a send could be settled before its own input had been
  submitted. On teardown, `stop` force-killed before the graceful path could run, so an in-flight
  send's caller got a dropped connection instead of its output and the control socket was left on
  disk; a killed session recorded `exit_code: 0` as though it had exited cleanly; and a
  process-group kill was skipped whenever the group leader had already exited, orphaning exactly the
  workers it was meant to reap.

### Changed

- `Session::PendingSend` now holds the settle decision, which the supervisor previously carried
  inline. Four review rounds had found defects in that logic, and none of them needed a pty to
  demonstrate yet none could be demonstrated without one; it is now testable on its own.
- CI installs a pinned `fledge` release asset instead of resolving "latest" through the
  unauthenticated GitHub API, which is rate-limited per IP and shared between runners. Four CI runs
  had been lost to `could not determine latest version`, each looking like a real failure.

### Documentation

- `rune session` is in the README at last — a capability entry and a worked example of driving one
  agent from another. Every command in that section was run before it was written.
- `docs/sessions.md` covers `--screen`, the bounded transcript, and every flag a reply can carry,
  with what each should make a caller do.
- Both record what running many sessions at once costs: about 23MB and 27 descriptors each, flat at
  24 and at 60 concurrent sessions. Concurrency itself held — 60 simultaneous starts, every send
  reaching its own session, nothing left running afterwards, and 30 simultaneous unnamed starts
  producing 30 distinct codenames.

## [v0.5.0] - 2026-08-15

Found by dogfooding: driving real agent CLIs through `rune session` and measuring what came back,
rather than reading the code. Every fix below was reproduced against a live agent before it was
written, and every regression test was checked against the unfixed code first.

**Upgrade from 0.4.0 is strongly recommended** — 0.4.0 silently fails to deliver most prompts to
Claude Code.

### Fixed

- **Prompts longer than about 64 characters were typed into an agent's composer and never sent**,
  while `rune session send` reported a clean `settled: true`. An agent prompt is almost always
  longer than that, so for the one thing this feature exists to do — an agent CLI driving another —
  sends were silently not being delivered to Claude Code. A TUI treats a large chunk arriving in one
  read as a paste, and a carriage return inside a paste is a newline in the composer rather than
  Enter. The terminator is now written separately, after the text has drained. Measured against
  Claude Code: before the fix only 61 characters submitted and 82 did not; after it, every length
  tried up to 262 submits, and grok and agy are unaffected either way.
- **A `--wait-for-regex` pattern could wedge the supervisor past its own timeout.** The match runs
  on the supervisor's only thread, so a catastrophically backtracking pattern blocked the event loop
  outright — it could not pump the pty, answer `stop`, or even check the send's own `--timeout-ms`,
  because that check lives in the same loop. Reproduced with `(a+)+\1$`, where the send was still
  blocked long after its 8s deadline. A match now gets a bounded budget where Ruby supports one, and
  exceeding it abandons the pattern with `regex_timed_out: true`. Ruby memoizes most textbook
  catastrophic patterns since 3.2, but not those using backreferences; **Ruby 3.0 and 3.1 have no
  per-`Regexp` timeout and remain exposed**, which is now a stated limitation.
- **A supervisor that died said nothing about why.** `meta.json` still read `state: running` with no
  exit code, no exit event was logged, and `supervisor.log` was empty. The cause is now written to
  the transcript as a `crash` event and to stderr, and the session is marked finished with exit code
  70 whatever path teardown took.
- **A bytes-vs-characters bug killed live agent sessions within a handful of turns.** Multibyte
  output arriving inside the echo grace window asked for more characters than existed and raised,
  taking the supervisor and the agent process with it — reproducible within 2–4 turns, and an agent
  TUI paints spinners and box-drawing rules constantly. Echo tracking now counts characters
  throughout, which also stops a non-ASCII prompt from eating the first characters of a reply.
- Erasing to the start of a line now includes the cell under the cursor, per ECMA-48, so a repainted
  line no longer keeps one character it should have lost.
- The terminator delay now holds under backpressure. It is measured from the last text byte actually
  going out rather than from when the send arrived, so a write delayed by a full pty buffer cannot
  land in the child's next read alongside the text.

### Added

- **`--screen` on `rune session send` and `read`** returns the rendered terminal alongside the byte
  stream. A full-screen agent interleaves its answer with its own repaints, so the byte stream holds
  every frame while the screen holds only what is displayed: grok's 361KB transcript renders to
  1.1KB, claude's 163KB to 2.4KB. Measured against grok, an answer the agent plainly displayed was
  absent from the byte stream 3/3 turns and present in the rendered screen 3/3. Opt-in, and rendered
  in the calling process so the supervisor's event loop is untouched. A cooked-mode shell barely
  changes, because it does not repaint.
- `Parsers::ScreenRenderer`, the terminal replay behind it. Deliberately not a full emulator: it
  implements what decides where text lands — cursor motion, erasing, line discipline — and consumes
  everything else, which by definition cannot change what is on screen.
- `busy_at_send` on a settle reply, reporting that the child was still producing output when the
  send landed.

### Changed

- **`--settle-ms` returns to a default of 800**, reverting the 0.4.0 change. That change was made on
  a measurement that was wrong twice over, and both faults were in the measuring harness rather than
  in settle: the claude figures used a prompt above the length that was never being submitted at
  all, and the grok figures searched the byte stream for an answer that repaints had split.
  Re-measured with both corrected and detection moved to the rendered screen, the reply was the
  answer to the question actually asked in **27/27 claude turns and 18/18 grok turns, at every
  window including 800ms** — with the longer window costing up to double the latency per call and
  buying nothing. The "previous turn's answer" failure that 0.4.0 documented as settle's
  characteristic weakness was an artifact and has not been observed since.

## [v0.4.0] - 2026-08-15

### Added

- `rune session` — persistent, named PTY sessions that outlive a single `rune` invocation, so one
  agent CLI can drive another conversationally instead of one-shot. `rune session start --name X --
  <cmd>` spawns the child under a detached per-session supervisor that owns the pty; `rune session
  send --name X "..."` writes to it and returns *only* the output that send produced; `rune session
  read`/`list`/`stop` cover the rest. Neither existing execution model could do this: `rune run`
  buffers and returns once, and `rune watch` hard-refuses to run without a human terminal on stdin,
  so an agent had no way to hold a REPL-shaped child open across calls.
- **Send-and-settle**, the primitive that makes the above usable: `--settle-ms` returns once the
  child has been quiet for N ms, `--wait-for-regex` returns as soon as output matches, and
  `--timeout-ms` caps the whole wait (reporting `settled: false`, `timed_out: true` rather than
  failing). Together these turn an async TTY into a synchronous request/response call. Settle-time
  is the primary completion signal deliberately: `prompt_detected` only matches shell-shaped
  prompts, so it is usually `false` for exactly the agent REPLs this exists to drive, and is
  reported as advisory metadata that never gates a reply.
- `rune session attach` connects your real terminal to a running session — output streams to the
  screen, keystrokes go to the agent, and the current screen is replayed on connect. **Ctrl-]**
  detaches and leaves everything running, which is the whole difference from `rune watch` (which
  owns the child it spawned). Ctrl-C deliberately still reaches the child so a runaway agent can be
  interrupted.
- Sessions are **named and project-scoped**. `--name` is optional for `start` — an unused
  `<tool>-<word>` codename is generated otherwise — and names are scoped to the enclosing git
  working tree, so `reviewer` in two checkouts is two sessions and neither is reachable from the
  wrong directory. `rune session list --all-projects` opts out of the scoping.
- `rune session archive` files a stopped session away, freeing its name and keeping history out of
  the live list; `rune session list --archived` shows it.
- `rune session list` reports `idle_ms` and a `last_line` summary per session, so "is this one stuck
  and what is it doing" is answerable at a glance when several agents are running.
- Session state lives under `RUNE_HOME` (default `~/.rune`) with owner-only `0700` directories and
  `0600` files, and each session's transcript is an NDJSON event log in the **same format `rune
  watch` already writes**, so `tail -f` works on a live session.

### Changed

- Examples are split by audience: `examples/agents/` (structured, programmatic) and
  `examples/humans/` (interactive programs meant to be driven from a terminal). Each folder has a
  README, and new examples cover the library surface, multi-session fan-out, failure handling,
  driving rune as a subprocess without loading the library, and a stand-in agent REPL that costs no
  API quota. The repository is now Ruby end to end — no shell scripts remain.
- CI no longer runs the Augur risk gate or Attest provenance verification, and `spec-sync` runs
  without `--strict`/`--stale`. The contract itself — specs matching code, coverage staying
  complete — is the part worth gating on; the rest was rejecting work for bookkeeping reasons
  rather than for drift between specs and code. To be revisited when spec-sync 6 lands, which
  reworks the change-verification model. The spec-sync job also no longer waits on the Ruby matrix:
  the two check different things and neither needs the other, so running them side by side returns
  a result in ~90s instead of ~2m40s. `scripts/trust_range.sh` and
  `scripts/squash_attest_forwards.sh` existed only to make those gates non-vacuous and are removed
  with them.

- **`--settle-ms` now defaults to 3000 rather than 800**, on measurement rather than taste. Driving
  Claude Code through 27 turns (three task shapes × three trials × three windows), the reply was the
  answer to the question actually asked in 5/9 at 800ms, 8/9 at 3000ms and 8/9 at 6000ms. The
  failure at 800ms was almost never a truncated answer — it was the *previous* turn's answer,
  returned whole and well-formed, which a caller cannot distinguish from a correct reply. 6000ms
  bought nothing over 3000ms and cost 2.5s per call. Sends against fast, non-agent children (a
  cooked shell) should pass a smaller `--settle-ms` explicitly; the default is now tuned for the
  agent CLIs this feature exists to drive.
- A send issued while the child was still producing output reports `busy_at_send: true` — the case
  where a reply is most likely to be the previous turn's answer. Reported rather than prevented:
  deferring the write until the child goes quiet needs another deferred state in the event loop.

### Fixed

- **A session driving a real agent CLI died within a handful of turns.** `echo_still_arriving?`
  bounded its loop by *byte* length while indexing by *character*, so any multibyte output arriving
  inside the echo grace window asked for more characters than existed, got `nil`, and
  `start_with?(nil)` raised — killing the supervisor and taking the agent process with it. An agent
  TUI paints spinners and box-drawing rules constantly, so this was the normal case for exactly the
  targets sessions exist to drive: reproducible within 2–4 turns, three runs out of three, and
  12/12 rounds clean after the fix. `beyond_echo` had the same mix-up in the other direction —
  advancing past the echo by its byte length overshot for any non-ASCII prompt and silently ate the
  first characters of the reply. Both now count characters throughout. Found by dogfooding; three
  rounds of independent code review did not.
- **A supervisor that died said nothing about why.** `meta.json` still read `state: running` with no
  exit code, no exit event was written to the transcript, and `supervisor.log` — the supervisor's
  own stderr — was empty, so every later command reported a session that was not there and nothing
  named the cause. The supervisor now records a `crash` event with class, message and backtrace to
  the transcript and to stderr, and exits `70` (sysexits `EX_SOFTWARE`, distinct from any status the
  child could return). Teardown marks the session finished no matter how it got there, so no path
  leaves a session claiming to be running.
- `Parsers::TextSanitizer` now strips private-parameter CSI (`\e[?1049h`, `\e[?2026h`), OSC strings
  (`\e]0;title\a`), DCS/SOS/PM/APC strings, and keypad/cursor-key modes, not just SGR-shaped
  sequences. The old pattern left a full-screen TUI's escape traffic almost entirely intact, so
  `clean_output` was unreadable for exactly the agent CLIs sessions exist to drive. Improves
  `rune run` on any TUI command equally.

## [v0.3.0] - 2026-08-14

### Added

- `rune run --max-output=BYTES` bounds `clean_output`/`raw_output` to BYTES each, keeping head and
  tail (the middle is omitted), reporting `truncated`/`omitted_bytes` in the result. `rune run
  --tail=N` keeps only the last N lines of each, reporting `truncated`/`omitted_lines`. Both are
  opt-in and mutually exclusive; the default result data shape is unchanged when neither is
  passed. Addresses #12 (`rune run` previously buffered a chatty command's entire output
  unbounded — 18.7MB of JSON from 5 seconds of `yes`).
- `rune watch --timeout=SECONDS` kills the session after N total seconds; `rune watch
  --idle-timeout=SECONDS` kills it after N seconds with no output and no input. Both are opt-in,
  may be combined, and default to unset (preserving today's unbounded interactive behavior). On
  expiry the child is killed and reaped, and the result reports `exit_code: 124`, `timed_out:
  true`, `timeout_kind: "timeout"|"idle_timeout"`. Addresses #14 (`rune watch` previously had no
  timeout anywhere in its path, so an agent driving a child that never exits hung forever with no
  recovery).
- `rune run --separate-streams` spawns stdout on a real pty and stderr on a plain pipe, adding
  `clean_stdout`/`clean_stderr` to the result alongside the existing merged `clean_output`/
  `raw_output` view. Opt-in — the wrapped child loses true controlling-terminal semantics on this
  path, which is why it isn't the default. Addresses #15 (previously stdout and stderr arrived
  merged with no way to distinguish them, a regression against plain `subprocess.run`).
- `--help` and `-h`, at the top level (`rune --help`) and per command (`rune run --help`), plus
  `rune help <command>`. Command help lists that command’s own flags — `--timeout=SECONDS`,
  `--log=PATH` — which were previously discoverable only from `specs/` and from the error you got
  for using them wrong.
- A `usage`/`flag` DSL on `Rune::Command` so each command declares its own invocation shape and
  flags next to the code that parses them.
- Help is a normal `Result`, so `rune run --help --json` returns `usage` and `flags` as structured
  data an agent can read without scraping the human rendering.

### Fixed

- `prompt_detected` in `rune run`'s result now reflects whether the *last* non-blank line of
  output looks like an interactive prompt, not whether any line anywhere in the entire run ever
  did. `rune run`'s result is only ever read after the process has already exited or been killed
  by `--timeout`, so "did a prompt-shaped line ever appear" was never the useful question — for a
  long TUI-heavy session it was nearly always `true` and told an agent nothing (#30, found via
  real dogfooding). Also fixes a related latent bug: on an actual `--timeout` kill,
  `prompt_detected` was unconditionally `false` regardless of what was actually on screen when the
  process was killed — exactly the case where the field is most useful.
- `rune --help` returned `Unknown command: --help` and exit 1; `rune run --help` tried to *execute*
  `--help` in a pty and exited 127.
- Route `rune watch`'s live passthrough to stderr in agent mode (`--json`, `--ndjson`, or piped
  stdout) so stdout carries only the result envelope. It previously emitted the wrapped command's
  raw output followed by the JSON, which meant `rune watch --json` produced stdout that did not
  parse.
- Compute an explicit, non-empty commit range for the risk and provenance gates, and fail when that
  range is empty. On a push to `main` the range resolved to zero commits, so both gates reported
  success while inspecting nothing.
- Derive push-event trust ranges from GitHub's exact before/after SHAs so a multi-commit push cannot
  leave earlier commits outside Augur and Attest while only checking the tip.
- Forward the provenance recorded on a squash-merged pull request head onto the landed commit, so a
  push to `main` is verified against the review that actually happened.
- Keep the non-PTY end-to-end examples loadable on platforms where Ruby's optional `pty` extension
  is unavailable, while skipping only the examples that genuinely require a PTY.

### Changed

- Assert end-to-end that the complete stdout of every command parses as a single JSON document, in
  every agent output mode.
- Exercise trust-range selection against real temporary Git histories, including a three-commit
  push, and simulate a Ruby installation without the `pty` extension.

## [v0.2.1] - 2026-07-28

### Fixed

- Preserve `--json` and `--ndjson` flags after the command separator instead of consuming flags
  intended for the wrapped process.
- Decode UTF-8 incrementally so multi-byte characters split across PTY reads remain intact.
- Mirror terminal dimensions into watched child processes and track resize changes while polling.
- Kill and reap watched children when an output sink closes with `EPIPE`.
- Create default watch logs as collision-safe, symlink-resistant, owner-only `0600` files.

### Changed

- Test every supported Ruby minor from 3.0 through 4.0 and enforce strict spec-sync, risk, and
  provenance gates.
- Include linked documentation and examples in the built gem and correct installation guidance.
- Add release version parity, package, smoke, and provenance checks before publishing.

## [v0.2.0] - 2026-07-27

### Other

- Bump version to 0.2.0 (3ef80d1)
- Fix 9 real issues from PR #3's automated review triage, update docs for 0.2.0 (d00a99e)
- 0.2.0 launch prep: PTY timeout flag, TableParser format option, docs, roadmap (#3) (2e68ad9)
