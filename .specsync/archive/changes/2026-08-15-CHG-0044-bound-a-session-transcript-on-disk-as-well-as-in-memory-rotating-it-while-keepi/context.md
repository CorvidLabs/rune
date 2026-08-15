---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: context
---

# Context

The previous change bounded what the supervisor holds in memory. This is the same problem on disk,
and it is the worse half: memory is reclaimed when the supervisor exits, the file is not.

`output.ndjson` is opened append-only with no ceiling and nothing ever prunes it. `store.remove`
is never called from the command layer, and `archive` *moves* the session directory rather than
pruning it, so the transcript survives the session indefinitely. A 150-second run at 500KB/s left
80MB behind.

Reading it was getting worse too: `transcript_for` rebuilds the whole transcript in the client on
every `read`, which on that file meant a 72MB string.
