---
change: CHG-0045-record-what-running-many-sessions-at-once-costs-measured-across-24-and-60-concu
artifact: design
---

# Design

Documentation only. The cost is inherent to the design — one supervisor process per session — and
the isolation it buys is the reason the design is that way: a wedged agent takes down its own
session and nothing else. Removing the cost would mean multiplexing sessions into one process, which
trades that isolation away.

So this is recorded as a known cost in the spec and explained in the guide, rather than treated as a
defect to fix.
