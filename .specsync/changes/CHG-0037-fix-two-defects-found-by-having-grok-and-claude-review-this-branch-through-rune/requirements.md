---
change: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
artifact: requirements
---

# Requirements

1. Erasure must include the cell under the cursor, in both directions, as ECMA-48 specifies.
2. The terminator delay must hold under backpressure, not only when the pty accepts the text
   immediately.
