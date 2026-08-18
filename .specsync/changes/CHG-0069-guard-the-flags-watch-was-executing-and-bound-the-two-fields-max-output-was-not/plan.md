---
change: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
artifact: plan
---

# Plan

The guard moves to `Command.flag_error`, with both message templates, and both
commands pass their own value-flag list. `run` keeps `VALUE_FLAGS` derived from
`FLAG_PATTERNS`; watch derives the timeout flags and appends `--log`, whose
pattern is inline in `scan_head` — the comment says so rather than claiming a
derivation it does not have.

`Transcript.grep_text` takes the text to search; `Transcript#grep` delegates with
`@text` so nothing else changes.

`bound_stream` applies the same budget to each separate stream and returns the
text untouched when no bound was asked for.
