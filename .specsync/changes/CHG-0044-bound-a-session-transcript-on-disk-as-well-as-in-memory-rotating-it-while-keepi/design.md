---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: design
---

# Design

When the transcript reaches `MAX_LOG_BYTES` the supervisor rotates it: the file is rewritten with a
`truncated` event carrying the cumulative dropped byte count, followed by the newest events whose
output totals at most `LOG_KEEP_BYTES`. The rewrite goes to a temporary file and is renamed into
place, so a reader never sees a half-written transcript.

Cursors stay absolute because the reader adds `dropped_bytes` to its running offset without
emitting text. That makes `cursor` in a `read` reply mean the same thing before and after a
rotation, and lets `--since` from after the cut land exactly. A cursor from before the cut returns
everything still held rather than nothing, and the reply carries `dropped_bytes` so the caller can
see that earlier output is gone.

The cumulative count is carried forward across rotations, so the arithmetic holds for a session
rotated many times.
