---
artifact: tasks
---

# Tasks

- [x] Per-IO write queue drained on writability; no blocking write left on the event-loop thread
- [x] Verify the queue delivers correctly (300KB byte-perfect against a child-computed byte sum)
- [x] Attach sends the terminal's dimensions; SIGWINCH forwarded over its own control connection
- [x] Restore the headless default when the last terminal detaches
- [x] Reap control connections that connect and never send
- [x] Exclusive per-name start lock spanning the conflict check and the pid record
- [x] Regression tests for all four
- [x] Remove the four closed entries from the spec's Known Limitations
- [x] Document the MAX_CANON 1024-byte silent-drop discovery in the spec and the guide
