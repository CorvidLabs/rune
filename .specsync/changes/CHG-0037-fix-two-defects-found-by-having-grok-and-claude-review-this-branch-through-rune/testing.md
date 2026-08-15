---
change: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
artifact: testing
---

# Testing

Three tests: erase back to the start of the line includes the cursor cell; erasing with the cursor on
the last column clears the line; and the terminator deadline moves into the future while text is
still queued.

All three fail against the unfixed code and pass against the fix. The delay test is white-box
because the condition it pins — a deadline in the past with an undrained outbox — cannot be produced
reliably from outside the process.

340 examples, 0 failures; lint clean.
