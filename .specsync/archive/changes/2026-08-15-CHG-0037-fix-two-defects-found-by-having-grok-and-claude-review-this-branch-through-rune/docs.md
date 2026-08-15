---
change: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
artifact: docs
---

# Docs

The parsers spec states that erasure is cursor-inclusive per ECMA-48 and why excluding it was wrong.
The session spec's terminator invariant now states that the delay is measured from the last text byte
going out, and what goes wrong if it is not.
