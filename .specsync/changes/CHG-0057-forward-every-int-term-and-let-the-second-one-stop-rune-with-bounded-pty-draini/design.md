---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: design
---

# Design

`SignalHandler.with_traps(pid, burst_window:, abort_after:)` now enqueues each trapped
signal on a `Thread::Queue` instead of holding one `pending` slot, and the yielded poll callable
drains that queue: it forwards every queued signal, then raises `SignalHandler::Aborted` once the
count within `BURST_WINDOW_SECONDS` reaches `ABORT_AFTER` (2). The queue matters because two Ctrl-Cs
inside one 0.2s poll interval used to overwrite each other, and the whole point of the ladder is
that the second signal is not lost. Forwarding happens before the raise, so the child always
receives the signal that ends the run. `Aborted` carries the signal name and its `128 + signo`
exit code.

Raising out of the poll — rather than returning a flag every read loop must remember to check —
guarantees no loop can silently ignore the abort. `PTYRunner#execute_pty` and
`PTYWatcher#run_session` catch it and build an ordinary result, so `rune run` still renders.

The reaping is deliberately not a blocking `Process.wait2`. `SignalHandler.reap(pid, grace_seconds:,
&drain)` gives the child a bounded grace period to leave on its own, then SIGKILLs it, then waits a
bounded time for it to become reapable — running the `drain` block on every poll. The drain is what
keeps the child's pty moving, and it is the only thing that clears the macOS wedge described in
research. Because the drain needs the pty reader, the abort is caught inside `read_pty_stream` /
`read_separate_streams` / `pump_output`, where the reader is still open, and re-raised afterwards;
the handlers further out keep a bounded reap as a net that normally hits `ECHILD` and does nothing.

`kill_orphaned_child` and `terminate_child` — the `--timeout`/`--idle-timeout`/EPIPE paths — now
route through the same bounded reap with `grace_seconds: 0`, preserving their straight-to-SIGKILL
semantics while removing their unbounded `Process.wait`. They cannot drain: Ruby's internal timeout
exception is not a `StandardError`, so it cannot be caught while the reader is in scope. A wedged
child is therefore given up on rather than waited for — a documented limitation, not a fix.

Once rune aborts, `with_traps` restores INT/TERM to their previous dispositions, so a third signal
during teardown kills rune outright. That is the intended last escape hatch, not an oversight.
