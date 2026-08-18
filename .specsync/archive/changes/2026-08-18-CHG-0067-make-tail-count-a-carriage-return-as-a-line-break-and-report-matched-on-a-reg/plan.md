---
change: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
artifact: plan
---

# Plan

`OutputLimiter.tail_lines` splits into segments that carry their own
terminator and keeps the last N. Rejoining with a chosen separator would have
rewritten a CR-repainted transcript as LF-separated text, which is a different
defect in the same field.

`PendingSend#timed_out` merges `matched: false` for a regex send only — a
non-regex send has no pattern and must not grow the field.

The documentation is corrected rather than the settle behaviour, and the spec
now records *why* the four-condition version was wrong, so the next reader does
not "fix" the code back to it.
