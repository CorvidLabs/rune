---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: context
---

# Context

A second review round ran four lenses over the 0.8.0 fixes and then tried to **refute** each finding
with an independent oracle and a control case. That verification step corrected 4 of 7 severity
claims and overturned the stated root cause on the two highest-impact findings — review alone would
have had me build the wrong things.

Two results changed what was worth doing. The roadmap's stated fix for the echo bug, locating it in
rendered text, was measured and came out **worse** than the shipped baseline. And 0.8.0's headline
settle fix turned out to be partial: it covers a child that echoes once, not one that redraws.
