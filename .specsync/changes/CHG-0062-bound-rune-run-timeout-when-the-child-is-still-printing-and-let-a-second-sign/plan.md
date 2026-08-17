---
change: CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign
artifact: plan
---

# Plan

Signals are enqueued on a `Thread::Queue` and drained by the poll callable, so
none are lost to the latch. The escalation is the `timeout`/`docker run`/`ssh`
ladder: forward, then abort on the second within 5s, then restore `DEFAULT`.

`SignalHandler.reap` is bounded at every step and takes a drain block, and the
abort is caught inside the read loops where the pty reader is still open —
draining the master is the only thing that frees a wedged child, so the rescue
has to live where the reader is still in scope.

The `--timeout`/`--idle-timeout`/EPIPE kill paths are bounded but cannot drain:
Ruby s internal timeout exception is not a `StandardError`, so it cannot be
caught while the reader is open. Those give up on a wedged child rather than
waiting for it — better than an unbounded wait, and recorded as a limitation
rather than dressed up as a fix.
