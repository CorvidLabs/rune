---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: research
---

# Research

Ruby memoizes most textbook catastrophic patterns since 3.2, and on Ruby 4.0 every one tried —
`(a+)+$`, `(a|a?)+$`, `(x+x+)+y`, `(a*)*$`, `(a|aa)+$`, `([a-zA-Z]+)*$` — completed
in under a millisecond. That optimization is disabled for patterns using backreferences, and those
still blow up: `(a+)+\1$` and `(a|a?)+\1$` both ran past 8 seconds on subjects of 41 and 33
characters.

So the exposure is not hypothetical on modern Ruby, and on 3.0/3.1 it covers the textbook patterns
too.

End to end before the fix: the send blocked past its 8s `--timeout-ms` and the loop never
recovered. After: it returns in under a second with `regex_timed_out: true`, and the next send on
the same session settles normally.
