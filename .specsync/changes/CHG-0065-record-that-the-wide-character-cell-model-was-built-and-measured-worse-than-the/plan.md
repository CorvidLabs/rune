---
change: CHG-0065-record-that-the-wide-character-cell-model-was-built-and-measured-worse-than-the
artifact: plan
---

# Plan

Rewrite invariant 17 around the live-output comparison, with the two synthetic
probes that reproduce it and an explicit note that a third does not distinguish
the two implementations.

State what the next attempt actually needs: a grid of cells rather than a String
per row, with every operation rewritten against it — which is the same change a
retained per-session `Screen` needs, so it should be done once and deliberately.

Zero-width characters are recorded with the same root cause: appending a
combining mark to its base cell puts every later index in the row off by one, so
the next graphic overwrites the mark. Measured, a decomposed `é` rendered `e`.
