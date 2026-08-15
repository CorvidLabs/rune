---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: docs
---

# Docs

The session spec states that the transcript file is bounded, that rotation keeps the recent tail,
and that cursors stay absolute across it with `dropped_bytes` reporting what is gone.
