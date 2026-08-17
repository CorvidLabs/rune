---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: docs
---

# Docs

No user-facing documentation changes. The behaviour is recorded in the canonical specs:
`pty_runner` gains invariants 24-26 (nothing swallowed; the second signal of a burst ends the run at
`128 + signo`; every wait bounded and the pty drained while the child dies), the matching
behavioural examples and error cases, and the new `SignalHandler` surface in its Public API table.
`watch` invariant 6 is rewritten to cover the ladder, why the missing default `--timeout` made this
the serious case, and why a human's Ctrl-C does not travel this path at all.
