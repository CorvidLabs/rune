---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: requirements
---

# Requirements

1. A cut inside an escape sequence must not put the remainder on the screen, at any offset.
2. The resync must be bounded: a stream whose next escape is far away, or absent, keeps its text.
3. What the window costs an agent that never erases must be documented, since it cannot be fixed.
