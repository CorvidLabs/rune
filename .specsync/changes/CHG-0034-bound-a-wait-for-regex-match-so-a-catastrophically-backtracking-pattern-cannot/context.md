---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: context
---

# Context

Found by a stress harness written after the 0.4.0 soak came back clean, probing the paths the soak
did not: concurrent agents, racing sends, oversized input, hostile regexes, mid-turn reads, and a
SIGKILLed supervisor. Everything held except one.

`--wait-for-regex` is documented as the deterministic escape hatch from the settle heuristic, and
the pattern it compiles comes straight from the caller. The match then runs on the supervisor's only
thread. A pattern that backtracks catastrophically therefore blocks the event loop outright: it
cannot pump the pty, cannot answer `stop`, and — the detail that makes this worse than merely
slow — cannot check the send's own `--timeout-ms`, because that check lives in the same loop.

Reproduced with `(a+)+\1$` against a child emitting 60 `a`s: the send was still blocked long
after its 8s deadline, and recovery needed `stop`.
