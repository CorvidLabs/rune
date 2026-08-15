---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: tasks
---

# Tasks

- [x] measure resident memory and descriptors over a running session
- [x] `@window_start`, `transcript_bytes`, `slice_from`, `trim_transcript`
- [x] never trim past a live send's cursor
- [x] regression tests, two verified failing against the unbounded version
- [x] re-measure clean, for long enough to distinguish a plateau from a slowdown
