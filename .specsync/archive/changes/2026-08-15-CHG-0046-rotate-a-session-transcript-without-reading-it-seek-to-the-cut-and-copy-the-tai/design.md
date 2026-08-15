---
change: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
artifact: design
---

# Design

Three things, each removing a reason to touch the data:

- **Seek instead of scan.** The cut point is found by seeking to `size - LOG_KEEP_BYTES` and
  advancing to the next line boundary, so the region being dropped is never read.
- **Read the count, not the event.** Every output event already records `bytes`, so the kept
  region is measured with a small regex rather than `JSON.parse`, which would materialize each
  line's text.
- **Copy with `IO.copy_stream`.** The kept tail moves kernel-side; the bytes never enter Ruby.

The total is supplied by the supervisor, which already tracks it as `transcript_bytes`, so nothing
has to be recomputed from the file.
