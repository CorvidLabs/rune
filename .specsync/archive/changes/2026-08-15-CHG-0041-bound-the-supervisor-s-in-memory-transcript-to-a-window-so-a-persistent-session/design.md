---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: design
---

# Design

The supervisor keeps a *window* plus `@window_start`, the absolute offset of its first byte.
`transcript_bytes` reports `@window_start + @transcript.bytesize`, so cursors are unchanged from
a client's point of view — and clients were never reading from this process anyway: `read` builds
the transcript client-side from `output.ndjson`.

That leaves only two consumers of the in-memory copy: the attach backlog, which needs the last 64KB,
and the pending send, which needs everything since its cursor. `trim_transcript` drops what is
older than both, and takes the *minimum* of the two floors so it can never outrun a live send.
