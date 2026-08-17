---
change: CHG-0063-assert-the-geometry-rune-guarantees-not-the-scheduler-that-usually-delivers-it
artifact: requirements
---

# Requirements

1. Both terminal-size specs assert the child ends up at the default, by either
   path.
2. The race is written down where the next reader will find it.
3. Nothing about the product changes — this release does not rewrite the spawn
   path on the strength of one CI failure.
