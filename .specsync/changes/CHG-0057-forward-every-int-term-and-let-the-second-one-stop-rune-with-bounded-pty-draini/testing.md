---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: testing
---

# Testing

423 examples, 0 failures. Twelve new ones.

Every new test was falsified against its own reverted fix, using five separate mutations rather than
one blanket revert, so each test is pinned to the specific behaviour it claims to cover:

- **M1, the original latch restored.** Six examples fail, including the two that reproduce the
  reported symptoms exactly: `rune run` reports 124 at its `--timeout` instead of 130, and
  `rune watch` survives past its join timeout.
- **M2, the abort raise removed.** Exactly the two escalation examples fail; the "forwards every
  signal" example still passes, which is correct — it is not about escalation.
- **M3, cumulative counting instead of a burst window.** Only the burst-window example fails.
- **M4, no SIGKILL after the grace period.** The reap example and both integration examples fail.
- **M5, the reap left without its pty drain.** The `rune run` integration example fails three ways:
  the child's second reply is missing from the capture, the run takes 6.6s instead of under 2, and
  the child is left behind.

Two fixture defects were found this way and are worth recording, because both are the failure mode
where a test cannot fail.

The first: "forwards every trapped signal" originally fired three signals back to back and asserted
the child saw three. That passed against the real fix and *also* failed against M2, which cannot be
right — M2 does not touch forwarding. POSIX signals are not queued, so two INTs landing on a
sleeping child microseconds apart legitimately collapse into one delivery; the example was measuring
the OS, not rune. It now waits for the child to acknowledge signal N before sending N+1.

The second was worse, and only running the real CLI caught it. The integration fixtures used a child
whose signal handler was silent. That fixture is more specific than the mechanism: it made the
examples pass against an implementation that hung the actual `rune run` for over three minutes,
because a silent child leaves nothing unread in the pty and so never triggers the macOS wedge. Both
fixtures now print from their handlers, which is what a real child does.

Real-CLI verification, beyond the suite. `rune run`: 2x SIGINT exits 130 in 1.6s with the child
reaped and both of its INT replies captured; 1x SIGINT is forwarded and the run continues to its
`--timeout` (124); the originally measured 4x SIGINT + 2x SIGTERM burst exits 130; 2x SIGTERM exits
143. `rune watch` under a real controlling terminal: 2x SIGINT exits 130 in 1.6s, and the measured
5x SIGINT + 5x SIGTERM case now exits 130 instead of needing SIGKILL. Three human Ctrl-Cs at that
same terminal reached the child three times with the session still running, confirming the raw-mode
byte path is untouched.
