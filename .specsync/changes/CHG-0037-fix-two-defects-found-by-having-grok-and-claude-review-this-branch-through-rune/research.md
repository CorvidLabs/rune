---
change: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
artifact: research
---

# Research

Verified before changing anything:

    rune renders: "  CD"
    ECMA-48 says: "   D"

and for the delay, by reading the loop: `drain_outbox(ready[1])` immediately precedes
`deliver_submit` in the same iteration, so nothing separates the tail of a drained write from the
terminator once the deadline has passed.

The dogfooding run that produced these also confirmed the branch's own fixes: 790-character prompts
submitted and answered on all three agents, and a soak of grok, agy, claude and bash at 15 rounds
each — 60 rounds of send/list/read/read-since plus stop/archive/restart — reported 0 anomalies.
