---
artifact: design
---

# Design

Seven defects, grouped by what they broke.

## The reply framing was wrong in two ways

`--wait-for-regex` matched the raw post-cursor slice, which includes the pty's echo of the input.
Waiting for a marker you just asked an agent to print — the normal use — returned the caller's own
words instantly. It now matches `beyond_echo(slice)`, the same view settle already used.

Fixing that exposed a second bug in `beyond_echo` itself: it required the echo to begin exactly at
the send cursor. The cursor is taken the instant input is written, so bytes the child was already
emitting land first and displace it. It now *locates* the echo within the slice, and recognises a
partially-arrived echo by its trailing bytes rather than the whole slice. Without this the first fix
held only about two runs in three.

## A caller could lose the session or hang forever

The in-flight send's socket was not watched, so a killed caller went unnoticed and `@pending` was
held for the whole `--timeout-ms` — two minutes at the default — refusing every later send. It is
now in the select set and released on EOF.

Symmetrically, `Client` had no deadline of its own. That is correct while the supervisor's guarantee
to always reply holds, but it does not hold when the supervisor is wedged, and the caller then hung
with no recovery. `send` now bounds its own wait at the requested timeout plus a margin.

## Lifecycle honesty

`await_ready` accepted `state: running` plus a socket without checking the supervisor was alive, so
`start` could report success for a session that had already died. It now requires liveness, and
fails immediately once the supervisor is gone instead of waiting out the start timeout.

## Teardown was too narrow

`PTY.spawn` gives the child its own session, and agent CLIs spawn workers. Signalling only the
recorded pid left those alive after `stop`, holding ptys and ports where they could collide with the
next session for the same tool. Teardown now signals the process group.

## Exposure and robustness

Only the leaf session directory was owner-only; `RUNE_HOME`, `projects/` and `sessions/` were 0755,
enough to enumerate which tools were being driven under which names.

A control client could also stall the single thread with a partial request line, and one failing
teardown step skipped the rest. Both are now bounded/isolated, along with `EACCES` presenting as a
crash and a full disk ending the session.

## Deliberately not fixed

Recorded in the spec's Known Limitations rather than half-done: attach does not copy terminal size,
writes to attached terminals are blocking (same shape as the documented pty-write limitation), idle
control connections are not reaped, and concurrent `start` of one name is narrowed but not airtight
without a lock file.
