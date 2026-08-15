---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: tasks
---

# Tasks

- [x] `MAX_LOG_BYTES`, `LOG_KEEP_BYTES`, `rotate_output`, `tail_events`
- [x] supervisor tracks written bytes and rotates at the ceiling
- [x] reader accounts for `truncated` events; `read` reports `dropped_bytes`
- [x] cumulative carry-forward across repeated rotations
- [x] four regression tests, all verified failing against the unbounded version
