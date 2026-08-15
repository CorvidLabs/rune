---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: requirements
---

# Requirements

1. The settle decision must be exercisable without constructing a supervisor, a pty, or a socket.
2. Behaviour must not change: every regression test from five rounds of review must still pass.
3. The supervisor must keep the parts that genuinely need the loop — the clock, the transcript,
   whether the child is gone, whether the terminator has gone out — and pass them in.
