---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: plan
---

# Plan

1. Derive the busy signal from the transcript, not the supervisor, so it survives the session.
2. Verify it actually discriminates rather than assuming the threshold is right.
3. Document `exit_code` where a caller reading about `rune run` would find it, not in the session
   guide.
