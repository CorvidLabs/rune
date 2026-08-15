---
change: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
artifact: design
---

# Design

**Erase (grok).** `Screen#erase_line` mode 1 kept the cursor cell, so `ABCD` with the cursor on
column 3 rendered `  CD` where a terminal leaves `   D`. Mode 0 was already correct. `ED 1`
delegates to it and was wrong by the same character.

**Delay (claude).** `deliver_submit` waited for the outbox to drain but left its deadline where it
was. `drain_outbox` and `deliver_submit` run in the same tick, so once a backpressured write
finished the already-past deadline fired microseconds later and the terminator landed in the child's
same read — the coalescing the delay exists to prevent, reintroduced exactly when the pty is under
pressure. The deadline now restarts while text is queued, so it measures from the last text byte
going out.
