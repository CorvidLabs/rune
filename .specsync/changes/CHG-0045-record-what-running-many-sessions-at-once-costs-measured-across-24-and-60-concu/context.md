---
change: CHG-0045-record-what-running-many-sessions-at-once-costs-measured-across-24-and-60-concu
artifact: context
---

# Context

Every measurement so far had been of a single session. The shape the feature is actually for — one
agent orchestrating several others — had never been measured at all.

It holds up. What the test found was not a bug but a cost, and one worth stating before someone
discovers it by fanning out to fifty agents on a laptop.
