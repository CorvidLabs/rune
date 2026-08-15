---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: plan
---

# Plan

1. Measure, since nothing had.
2. Establish which consumers actually need the in-memory copy — it turned out to be two, and
   `read` was not one of them.
3. Window the buffer, keeping cursors absolute.
4. Re-measure on a clean machine state, long enough to see whether it plateaus or merely slows.
