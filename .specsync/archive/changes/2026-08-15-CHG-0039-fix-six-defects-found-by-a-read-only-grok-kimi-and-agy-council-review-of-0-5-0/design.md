---
change: CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0
artifact: design
---

# Design

**Renderer (grok).** `ESC D`/`E`/`M` now map to index, next line and reverse index; `ESC 7`/`8`
and CSI `s`/`u` save and restore the cursor; `VPA` moves the row and leaves the column; `ICH`,
`DCH`, `ECH`, `IL`, `DL`, `SU` and `SD` are implemented; vertical tab and form feed are
line-feed class motion rather than text. The last column follows xterm's deferred wrap — the cursor
stays on the last cell with a pending wrap that any explicit move clears — because the previous
state, one past the end, is one no terminal uses and every relative move read it wrong.

**Send path (kimi).** `handle_send` refuses while `undelivered_input?`, rather than letting
`flush_submit` append a terminator to still-queued text. `pending_outcome` splits: while the
terminator is owed only the deadline and child exit can end the wait, because nothing already on
screen can be an answer to input the child has not received.

**Teardown (agy).** `stop` calls `await_exit` between the graceful request and the kill, bounded
by the same timeout. `terminate_child` keeps the status from the wait it already performs.
`kill_process_group` drops its leader-alive guard, since signalling a group with no members raises
ESRCH, which the existing rescue handles.
