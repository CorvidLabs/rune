---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: research
---

# Research

Writing 40MB of output through the supervisor's log path:

| | |
|---|---|
| output written | 40.05 MB |
| peak file size | 32.00 MB (the ceiling) |
| final file size | 15.94 MB |
| retained text | 15.93 MB |
| dropped_bytes | 24.13 MB |
| dropped + retained == written | exact |
| recent marker retained | yes |

Cursor behaviour across the rotation: one taken afterwards resolves to exactly the expected bytes,
one from before it returns everything still held.

Before this, a 150-second session at 500KB/s left an 80MB file, and reconstructing it in the client
produced a 72MB string on every `read`.
