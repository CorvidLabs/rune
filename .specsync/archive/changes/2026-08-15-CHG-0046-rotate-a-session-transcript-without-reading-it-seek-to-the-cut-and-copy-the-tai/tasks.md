---
change: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
artifact: tasks
---

# Tasks

- [x] reproduce the jump and tie it to the rotation
- [x] seek to the cut instead of scanning the dropped region
- [x] read the recorded byte count instead of parsing events
- [x] copy with `IO.copy_stream`
- [x] confirm the accounting is still exact
- [x] re-run the 45-minute scenario
