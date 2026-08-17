---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: requirements
---

# Requirements

1. Every trapped INT/TERM reaches the child, in arrival order, for as long as the
   run lasts. Two signals arriving inside one poll interval are both delivered.
2. The second signal of a burst is forwarded to the child and *then* ends the run.
3. A single signal is still the child's alone: it is forwarded and rune keeps waiting, so the traps
   keep doing what they were installed for rather than rune dying instantly and orphaning the child.
4. Signals further apart than the burst window are independent first signals.
5. An ended run returns a well-formed result at the conventional `128 + signo` status, rendered
   normally — not a process dying mid-render.
6. The child is reaped on every path touched, and every wait on it is bounded.
7. `rune watch` with no `--timeout` is bounded by the same ladder.
