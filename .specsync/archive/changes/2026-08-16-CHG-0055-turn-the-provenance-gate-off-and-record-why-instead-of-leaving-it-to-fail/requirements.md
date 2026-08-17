---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: requirements
---

# Requirements

1. A release must be cuttable without a manual signing step.
2. The off state must be **declared**, not implicit — a reader should find out why from the
   repository, not from its history.
3. The validation that actually prevents a wrong release — exact tag, tag reachable from main,
   tag matching the packaged version — must be untouched.
