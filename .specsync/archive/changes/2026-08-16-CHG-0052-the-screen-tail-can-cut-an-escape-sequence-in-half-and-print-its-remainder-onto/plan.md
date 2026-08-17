---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: plan
---

# Plan

1. Resync the cut to the first escape, bounded.
2. Test at every offset within a sequence, plus the two cases the bound protects.
3. Document what the window costs an agent that never erases, and that a duplicated line from such
   an agent may be faithful.
