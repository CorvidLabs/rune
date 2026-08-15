---
change: CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic
artifact: design
---

# Design

`DEFAULT_SETTLE_MS` returns to 800. The corrected data shows no benefit from a longer window and a
real cost: grok's average round trip went from 8.7s to 16.8s, roughly double, for identical results.

The constant's comment and the spec's Known Limitation both now carry the corrected figures, an
explicit note that the 0.4.0 measurement was confounded and how, and the boundary of what the new
evidence supports — two agents, 45 turns, both driving TUIs whose spinner runs for the whole turn,
which is precisely what makes byte silence a reliable completion signal.

`busy_at_send` stays. It costs one comparison and remains the honest report for a send that lands
while the child is still talking, even though the failure it was introduced to surface turned out to
be an artifact.
