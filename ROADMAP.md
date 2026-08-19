# rune roadmap

Release history lives in [`CHANGELOG.md`](CHANGELOG.md). This file records only where rune is now
and what stands between it and 1.0.

Until 0.8.0 this document was a tracking issue for 0.2.0, three releases out of date, still listing
"remaining limitations" that had been fixed and describing a scope that had since been overridden
twice. A roadmap that describes a version nobody is running is worse than no roadmap, because it is
read as current.

## Where rune is

Three execution models, all documented and all exercised by the test suite against real pseudo
terminals:

| model | what it is for |
|-------|----------------|
| `rune run` | one command, buffered, structured result |
| `rune watch` | live bidirectional passthrough, requires a human terminal |
| `rune session` | named PTY sessions that outlive the invocation, driven by send-and-settle |

Zero runtime dependencies, Ruby 3.0 through 4.0, 100% spec coverage enforced in CI.

The public surface has not broken since 0.4.0. Every release since has added flags and reply fields
or corrected documentation; nothing has been removed or changed meaning.

## What 1.0 needs

1.0 is a statement that the surface is stable and the known defects are known. **It is not a
statement that the defects are fixed** — that reading is what kept this list growing, because every
unsolved item looked like a blocker whether or not anyone intended to solve it.

So the items below are split by what would actually change:

- **Gates** — things that must be *done* before 1.0. There is one left.
- **Documented limitations** — things that will ship unfixed, deliberately, described accurately.
  These moved out of this section rather than being resolved, and each says why.

The half-painted `--screen` frame is not here: it remains unreproduced, two candidate fixes were
measured and rejected, and it lives under
[Known and documented](#known-and-documented-not-planned-for-10). The 0.8.0 renderer row
(alt screen, wide characters, DEC line drawing, IRM, DECAWM) is **closed** — modes and charsets in
CHG-0064, the cell model in #66.

### The remaining gate

**A final independent review round, and the surface-freeze decisions it surfaces.** Most of the
sharpest bugs in this project were found by an agent other than the one that wrote the code, so 1.0
should not be cut without another round. That round has now run — five reviewers, two driven through
`rune session` — and both agents answered *do not ship*. What they found in code is fixed
(CHG-0079: a control-socket request could kill a child; `read` reported dead sessions as running;
two parsers disagreed about what an escape is). What remains is a set of **additive** contract
decisions that are cheap now and impossible after a freeze: structured error codes alongside the
prose, `list --archived` returning a `name` other verbs accept, and a discriminator for synthesized
`exit_code` values. Those are the last thing standing between here and a cut.

### Moved to documented limitations

The three technical items that used to head this list are now under
[Known and documented](#known-and-documented-not-planned-for-10), unchanged in substance:

- **The settle path can return your own input.** Four rules measured and rejected, each with a
  documented opposite failure mode.
- **`--wait-for-regex` matches the byte stream, which is the wrong surface.** The fix is understood
  and its cost is measured; what is missing is a retained `Screen` wired into the supervisor.
- **The retained per-session `Screen` is not wired in.** The renderer half landed in CHG-0077 and
  the resize semantics were decided from xterm's source, but nothing feeds it chunk by chunk yet.

Each is real, each is measured, and none of them is going to be solved by holding the version
number. The detail that used to live here is kept below rather than deleted, because the record of
what was tried is the part that stops it being tried again.

- **The settle path can return your own input as the answer, when the child redraws it.** This is
  the sharpest defect in rune. `--settle-ms` waits for output that is not the echo; a line editor
  that repaints the line on submit sends the input a *second* time, and that copy counts as the
  child having spoken. Measured: `irb` and `python3 -q` settle in about a second with only the echo,
  3/3 each, while the answer arrives seconds later and lands in the next call. `bash -i` is
  unaffected, wrapped inputs included.

  **A rule was tried and disproved, which is worth recording so it is not tried again.** Anchoring
  on the *last* copy of the condensed echo — treat the send as unanswered when nothing follows it —
  fixes irb, python3 and wrapped bash 12/12. It also breaks any child whose reply *ends with* the
  request: the existing test child answers `REPLY:ping` to `ping`, the anchor lands inside the
  answer, and the send waits out its timeout. Removing every copy instead leaves irb's `>>` prompt
  behind, which is real output and not an answer, so coverage-based rules cannot separate the two
  either. The distinguishing signal is that a repaint is *preceded by cursor motion* while an answer
  is not, and that information is destroyed by the condensing the located-echo search depends on.
  A fix has to reconcile those two.

  **An outside review (grok, asked through rune itself) called this unsolvable
  by the current approach, and it is hard to argue.** Three rules, three
  opposite failure modes, all measured: stripping every echo copy leaves the
  child's prompt and starts too early; anchoring on the last copy scores 12/12
  and then breaks any reply ending with the request; classifying repaint against
  speech turns "answers too early" into "never answers at all". The condensing
  that makes an echo findable is the same step that destroys the cursor motion
  which would distinguish it from speech. That is a property of the approach,
  not bad luck.

  **The suggested alternative was to stop guessing and let the reply say how
  much of itself was the caller's echo.** It was implemented and reverted the
  same hour, because it fails on the case it exists for: `irb` reports 2
  characters beyond the echo, correctly, but `python3 -q` reports 951 while the
  answer is *absent*, because a per-keystroke repainter emits hundreds of
  partial echo prefixes and only whole copies can be stripped. A field reading
  951 for "nothing arrived" is the same silent lie wearing a new name.

  So the honest position is: the classification is unsolved, and quantifying the
  uncertainty is unsolved by the same mechanism. What is left is to stop making
  quiet-settle the *default* path for children that repaint — the reply cannot
  yet tell you, so the API should not imply that it can.

- **`--wait-for-regex` matches the byte stream, which is the wrong surface — but the screen is not
  simply the right one.** Reported from real use: in one session with one sentinel, the flag produced
  a false positive on the caller's own composer echo *and* a false negative on the child's real
  output, because the TUI split the token across a wrap boundary.

  Both halves reproduce, and the second half of the reporter's conclusion does not. Harnesses are in
  `harnesses/wrap_reassembly.rb` and `harnesses/composer_echo.rb`.

  | mechanism | byte stream | rendered screen |
  |---|---|---|
  | **split by streaming token paint** | **not found** | found |
  | token split by cursor positioning | **not found** | found |
  | token wrapped at the right margin | found | **not found** |
  | caller's prompt in a composer box | false positive | **false positive** |

  The first row is the structural one, identified from raw bytes by the reporter and reproduced here
  independently. A streaming agent paints each model token as its own positioned write, so
  `RUNE_TASK_COMPLETE_573` arrives as `RUN` + `E` + `_TASK` + `_COMPLETE_573` at adjacent columns, in
  different pty reads. Measured on a 5.5MB grok transcript: `"WROTE: /private/tmp/claude-501/…"` is
  **absent from the byte stream and present on the screen**. Meanwhile the caller's own prompt is
  contiguous, because a paste is painted in one go.

  So the byte stream does not merely *sometimes* miss the child and match the echo — for any sentinel
  longer than one model token it is **guaranteed** to, at boundaries chosen by a tokeniser nobody
  controls. That is the crispest statement of the bug.

  **Neither surface is correct for both fragmentation mechanisms, and neither excludes the echo.** A
  margin wrap emits contiguous bytes that the *terminal* splits across two rows, so the stream has
  the token and the render does not; cursor positioning is the exact reverse. And a regex against the
  screen matches `\| When finished print exactly RUNE_TASK_COMPLETE_573` in a composer box just as
  the byte stream does — a human reading `--screen` can see that is the composer, a pattern cannot.

  So "match the screen instead" is not the fix, and neither is "match the stream". What the evidence
  actually supports is **matching both surfaces, with the echo veto applied to each** — succeed if
  either fires, having excluded copies of the caller's own input. rune already owns every piece of
  that: condensed echo location, `Echo#repaint?`, and a bounded renderer.

  The complete fix is therefore **screen matching plus the echo veto rune already has** — condensed
  location and `Echo#repaint?`, built for the byte path. The open question is cost: matching per tick
  would render the grid on every pty read, and per-tick cost is what made the send path quadratic
  twice. A settle-time check is cheap and fixes the wrong-answer case while giving up the early
  return that is the flag's whole point. Neither is measured yet, and this is the item most likely to
  be got wrong in a hurry — four rules have already failed on the adjacent settle problem.

  **A fifth false-positive, distinct from the composer-box row: a reprint of an earlier answer.**
  `Echo#repaint?` vetoes a match covered by a copy of *this send's* input. It does not veto a match
  that is a reprint of *earlier output*. A child that reprints its scrollback on every input, then
  works, then prints a new answer, puts the previous turn's sentinel on the wire as ordinary new
  bytes. Measured on current main (`ruby -Ilib bin/rune`), child reprints then sleeps 3s then
  prints `DONE N`:

      send1  --wait-for-regex 'DONE \d+'   3.56s  matched=true   output holds DONE 1
      send2  --wait-for-regex 'DONE \d+'   0.56s  matched=true   output holds DONE 1 only

  `DONE 2` was not in the captured output. Two candidate rules were considered and not shipped.
  Rejecting a match whose text existed before the send loses a second `echo DONE` to a simple
  child — the reused-exact-sentinel case with no reprint. Rejecting a match preceded by
  cursor-home / erase loses a TUI that paints a reused sentinel with cursor motion as the real
  new answer. Unique-per-turn sentinels work: `--wait-for-regex 'DONE 2'` waits through the
  reprint. That is the documented answer until a retained `Screen` can tell a reprint from a new
  occurrence. The guide no longer calls the flag deterministic.

- **A retained per-session `Screen` is the fix, and it is now specified rather than hoped for.** It
  removes the render window instead of tuning it, which is what makes every constant above
  unnecessary, and it takes per-tick cost from ~262KB re-processed to the ~277 bytes that actually
  arrived — which is also what makes screen-based `--wait-for-regex` matching affordable. The whole
  chain hangs off it.

  Measured, by the spec-sync session and reproduced here on a second corpus: feeding pty chunks into
  one retained renderer **diverges** from a one-shot render — 3297 bytes against 2980, 28 of 40 lines
  differing on their corpus. The cause is not scroll, insert/delete or save/restore; those are
  `Screen` state and `Screen` is retained. **The parser is stateless between calls**: `render` builds a
  fresh `StringScanner`, so an escape split across a chunk boundary fails to match CSI, falls through
  to `PRINTABLE`, and is written onto the grid as literal text. The divergent lines are escape
  fragments — a bare `H`, a `108;`, an `m│`.

  Holding back a trailing partial escape and prepending it to the next chunk makes both corpora
  byte-identical to the one-shot render. Validated independently here: 2980 == 2980.

  **The UTF-8 half of that carry already exists and is already on this path.** `UTF8StreamDecoder`
  keeps a `@pending` byte suffix across reads and `supervisor.rb` decodes every pty read through it
  before the text reaches the transcript. That is also why a transcript replay shows zero
  invalid-encoding chunks: the split was resolved before it was ever written. So a retained grid needs
  the escape carry only, and must sit *after* the existing decoder rather than replacing it.

  Still open, and the only thing that is: **resize**. A retained grid has to be rebuilt rather than
  reflowed when `attach` changes the geometry, and that is precisely the boundary where the two
  reference emulators disagree with each other, so there is no oracle to appeal to.

- **Independent review.** Most of the sharpest bugs in this project were found by an agent other
  than the one that wrote the code: the ECMA-48 erase semantics, the `ESC D` that printed a literal
  `D`, every item in 0.7.0, and nine more in 0.8.0. That is evidence about method, not luck, and
  1.0 should not be cut without another round of it.

## The 0.8.0 review round, re-measured

All eight were found in the 0.8.0 review, all reproduced then. Each was re-run against the tree
rather than carried forward on the strength of the table, and seven are closed:

| finding | status |
|---|---|
| `--max-output` splices head and tail with no marker | **fixed** — `[rune] ==== 1517 bytes omitted by --max-output ====` |
| an unparseable `--grep` returns the *whole* transcript | **fixed** — returns nothing and says why, quoting Ruby's own reason |
| one oversized send bricks a cooked-mode session | **fixed** — see below; the entry was also wrong about the mechanism |
| a failed transcript write desynchronises cursors permanently | **fixed** — CHG-0057 records each dropped region and maps cursors through it |
| `archive` can orphan a live child | **fixed** — verified by killing the supervisor and archiving underneath it |
| unknown flags are typed at the child | **fixed** — `--settle_ms` now returns `Did you mean --settle-ms?` |
| `send` ignores `--max-output`/`--tail` | **fixed in 0.9.0** — and the two are now mutually exclusive, as `rune run` already had them |
| renderer: alt screen, wide characters, DEC line drawing, IRM, DECAWM | **fixed** — modes/charsets in CHG-0064; cell model in #66, after an earlier attempt was reverted on a misattributed A/B |

**A ninth, found after that table was written and not on it.** `rune run --timeout` never returned
when the child was still printing — the flag that exists to bound a run did not bound it. Present in
every release through 0.8.0, missed by every review round, and missed because every fixture used a
silent child: the trigger is unread bytes in the pty buffer at the moment of the kill, not a child
that ignores signals. Fixed in 0.9.0 with bounded, pty-draining reaping. The lesson is the one this
file already records in another form — a fixture more specific than the mechanism produces a test
that cannot fail, and this one hid a hang in the oldest command for nine releases.

**The correction to the oversized-send entry was itself wrong, and this is the worst harness error
in the file because it retracted a true finding.** The 0.8.0 entry claimed "every later send is
silently discarded while `settled: true`". That was retracted here on the strength of a
20,000-character send to `python3 -q`, which does receive its input in full (`LEN=20000`,
sha256-verified) and does refuse an overlapping send with a specific error. Every fact in that
retraction reproduces. It refuted nothing, because **`python3 -q` is in raw mode at the instant the
bytes land, and the original claim was about cooked mode.** The retracted claim is true, and
reproduces verbatim:

    cooked child, 1024-byte line, then five ordinary sends over two minutes
    every send:  status ok, settled true, state running, exit_code null
    child's own log after recovery: the 1024-byte line and all five probes are ABSENT, permanently

Measured with the child writing byte counts to a *file* rather than echoing, so the tty echo cannot
be mistaken for delivery, and with a post-recovery read proving the input was never merely delayed.

What is actually true, established by three independent instruments and an adversarial pass:

- **The limit is 1024 bytes per canonical line including the terminator**, so a caller's payload
  budget is 1023. At exactly 1024 all the payload is accepted and *the terminator is the byte that
  is rejected*, which is why the line can never be submitted and the queue never drains.
- **It is not one lost line. The session stops accepting input entirely**, indefinitely, while every
  reply says `settled: true, state: running`. `^U` (VKILL) clears it; `^D` does not and does not kill
  the child; `^C` ends the session at 130.
- **It is not rune.** A single 1025-byte `write()` to a bare `PTY.spawn` wedges identically, so
  rune's split payload/terminator write is not the cause. This is the macOS line discipline.
- **The discriminator is the tty's ICANON state when the bytes land** — proven by holding the child
  binary constant and flipping one termios flag. Not the child's identity: `cat`, a `sh` read loop, a
  Ruby loop and a child not yet reading all wedge identically. Not whether the child drains.
- **"Raw-mode children are unaffected" is false**, and this is the part that matters for rune's
  actual targets. `bash` and `python3` are raw *at their prompt* and **cooked while a foreground
  command runs**. Sending 1200 bytes to a busy `bash` loses the line and silently corrupts the *next*
  command; the same send to a busy `python3` leaves the follow-up statement unexecuted. The predicate
  is when you send, not what you started.
- **"Over-long line" is the wrong description at the caller's level.** Four 256-byte writes with no
  terminator wedge the queue just as well, and so does `--no-newline` with 1024 bytes and no
  terminator ever sent. The trigger is an unterminated canonical line reaching 1024 bytes.
- **There is no reliable in-band detector.** BEL fails in both directions: `--no-newline` at 1024
  emits none while already wedged, and a child that legitimately rings the bell is byte-identical to
  a wedging send. BEL is a function of `IMAXBEL`; with it cleared macOS discards in total silence.

The `~10 s to drain 20 KB` figure was machine-specific (~4.6 s here, superlinear: ~26 s for 60 KB),
and the overlapping-send refusal starts at 1024 bytes rather than between 10,000 and 12,000.
Complete lines are never silently lost — they get real backpressure and a loud refusal. Only
*unterminated* input disappears.

Two harness errors produced this entry's history and both are worth keeping. The first probe
reported "bricked" because its liveness helper ignored `status`, so a correct refusal read as a dead
session. The retraction above then measured the *wrong regime* and generalised from it — the same
shape of mistake, one level up: a fixture more specific than the mechanism. The rule that catches
both is to name the regime a measurement is in before publishing a claim that spans regimes.

## Known and documented, not planned for 1.0

Recorded rather than fixed because the candidate fix measured worse than the limitation, or because
there is no oracle to check an implementation against.

- **The half-painted `--screen` frame.** Reported from field use, reproduced by the reporter, not
  reproduced here. Two candidate fixes were measured and rejected — one measured *worse* than doing
  nothing. Documented in [`docs/sessions.md`](docs/sessions.md) with a workaround (poll twice,
  require agreement). Resolving it needs the reporter's full transcript.

- **`--wait-for-regex` can match a prior turn's reprint.** See the 1.0 item above for the
  measurement and the two rules that were not shipped. Unique-per-turn sentinels, or a file the
  child writes, are the workaround. `child_busy` will not wait through a silent think after the
  reprint. A heuristic here is the same class of mistake as the
  four settle rules.

- **There is no content search that agrees with the screen for a repainting child.** `--grep` matches
  the ANSI-stripped transcript, so overwritten history still matches and comes back as a clean line,
  and a cursor-painted frame is one long line — `--context` is inert there and a match can return the
  whole frame. Grepping the *screen* instead was rejected: it loses scrollback, which is the reason
  `--grep` exists (finding one line in a 379KB transcript), and measured, only 39 of 200 lines were
  on screen. The help text claimed "rendered text" and was wrong; that is corrected.

- **`run` and `session read` bound `clean_output` by opposite rules.** `run` bounds each field
  independently to the same budget, so the two describe different windows; `session read` derives
  clean from the bounded raw, so they agree. Both are right for their own contract — `run`'s flag
  promises "BYTES each" — and unifying them would cut `run`'s readable payload by the ANSI fraction
  on every colour-emitting child. Documented on both surfaces instead.

## What is deliberately not planned

- **Incremental streaming for `rune run`.** It buffers a whole run and returns one result;
  `--ndjson` changes the envelope, not the timing. `rune watch` is the streaming model. Documented
  rather than fixed, because the two models exist for different jobs.

- **Interpreting agent output.** rune is a pty. If a callee grows a machine-readable mode, rune
  passes it through unchanged; it will not parse an agent's prose into structure.

- **A session cap.** There is none. Each live session costs roughly 23MB and 27 descriptors, flat
  and linear — measured at 543MB for 24 sessions and 1361MB for 60. The limit is your machine's,
  and rune should not invent a smaller one.
