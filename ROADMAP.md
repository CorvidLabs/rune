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
