---
change: CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e
artifact: plan
---

# Plan

1. Reproduce the reported output exactly before changing anything.
2. Check the wrappers around the pump first — a wrapper that dropped the block's value would have
   explained it — and rule them out.
3. Separate "was attached" from "did detach".
4. Verify both paths, not just the fixed one.
