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

1.0 is a statement that the surface is stable and the known defects are known. Two things stand in
the way:

- **The half-painted `--screen` frame.** Reported from field use, reproduced by the reporter, not
  reproduced here. Two candidate fixes were measured and rejected — one measured *worse* than doing
  nothing. Documented in [`docs/sessions.md`](docs/sessions.md) with a workaround. Resolving it
  needs the reporter's full transcript, to replay the whole stream against the truncated window and
  see which one produces the tear.

  Note the roadmap previously named "locate the echo in rendered text" as the likely fix for the
  related `--wait-for-regex` bug. That was measured and **rejected** — it scored worse than the
  baseline and was the most expensive option tried. Condensed-text location is what worked.

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

## Known, unfixed, and queued for 0.9.0

All found in the 0.8.0 review round, all reproduced, none yet fixed:

| finding | why it matters |
|---|---|
| `--max-output` splices head and tail with no marker | turned `/bin/zsh` into `bin/zsh` — plausible text that never existed |
| an unparseable `--grep` returns the *whole* transcript | 17MB under `status: ok` for a typo; the safe fallback is nothing, not everything |
| one oversized send bricks a cooked-mode session | every later send is silently discarded while `settled: true` |
| a failed transcript write desynchronises cursors permanently | `send` and `read` disagree forever, with no `dropped_bytes` to signal it |
| `archive` can orphan a live child | when the supervisor is already dead, the child survives and becomes unnameable |
| unknown flags are typed at the child | `--settle_ms` became part of the prompt instead of an error |
| `send` ignores `--max-output`/`--tail` | accepted silently; the one call an agent makes most has no output bound |
| renderer: alt screen, wide characters, DEC line drawing, IRM, DECAWM | narrower than the above, all verified against two reference emulators |

## What is deliberately not planned

- **Incremental streaming for `rune run`.** It buffers a whole run and returns one result;
  `--ndjson` changes the envelope, not the timing. `rune watch` is the streaming model. Documented
  rather than fixed, because the two models exist for different jobs.

- **Interpreting agent output.** rune is a pty. If a callee grows a machine-readable mode, rune
  passes it through unchanged; it will not parse an agent's prose into structure.

- **A session cap.** There is none. Each live session costs roughly 23MB and 27 descriptors, flat
  and linear — measured at 543MB for 24 sessions and 1361MB for 60. The limit is your machine's,
  and rune should not invent a smaller one.
