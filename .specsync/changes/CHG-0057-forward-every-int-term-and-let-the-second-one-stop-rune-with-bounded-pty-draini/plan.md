---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: plan
---

# Plan

1. Replace the latch in `SignalHandler` with a queue-drained forwarder plus burst-scoped
   escalation and the `Aborted` error.
2. Add the bounded, drain-aware `SignalHandler.reap`.
3. Catch `Aborted` in `PTYRunner`'s two read loops and in `PTYWatcher#pump_output`, reaping there
   with the pty reader still open, and build interrupted results in the outer handlers.
4. Route the existing timeout/idle-timeout kill paths through the bounded reap.
5. Cover each behaviour with a test, and verify each test fails with its own fix reverted.
6. Re-verify against the real CLI, under a real controlling terminal for `rune watch`.
