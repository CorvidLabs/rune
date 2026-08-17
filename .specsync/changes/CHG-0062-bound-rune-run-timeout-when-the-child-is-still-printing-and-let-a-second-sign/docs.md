---
change: CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign
artifact: docs
---

# Docs

CHANGELOG carries both entries with the ladder measurements. ROADMAP records this
as a ninth finding that was not on its re-measured table, and why nine releases
of tests missed it: a fixture more specific than the mechanism produces a test
that cannot fail.

The limitation on the `--timeout`/`--idle-timeout`/EPIPE paths is written down in
`pty_runner.spec.md` invariant 26 and beside `kill_orphaned_child`, and the
macOS-only scope of the measurement is stated rather than generalised — there was
no Linux host to check it on.
