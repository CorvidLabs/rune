---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: testing
---

# Testing

Two integration specs: one asserts the send returns well inside its `--timeout-ms` with
`regex_timed_out: true`, the other that a normal send on the same session still settles afterwards.

Verified both ways. Against the unfixed supervisor both fail, and the run takes 76 seconds because
the wedge holds the loop until the client-side ceiling fires; against the fix both pass in 1.7
seconds.

Both skip on Ruby below 3.2, where no per-`Regexp` timeout exists and the limitation is documented
instead.

338 examples, 0 failures; lint clean.
