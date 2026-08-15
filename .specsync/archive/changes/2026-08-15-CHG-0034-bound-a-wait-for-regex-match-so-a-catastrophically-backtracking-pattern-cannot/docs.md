---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: docs
---

# Docs

The session spec gains an invariant describing the bound and why abandoning beats retrying, and a
Known Limitation stating plainly that Ruby 3.0 and 3.1 remain exposed.
