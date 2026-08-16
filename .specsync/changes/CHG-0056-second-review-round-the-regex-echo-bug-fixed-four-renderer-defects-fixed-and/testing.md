---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: testing
---

# Testing

411 examples. Two existing tests failed and **both were right to fail**: one encoded RIS being
consumed but not acted on, the other the old rule of handing back an unlocated slice inside the echo
grace window. Each was retargeted at the new deliberate behaviour rather than deleted.

The part worth keeping is what testing stopped. A rule anchoring on the last copy of the condensed
echo fixed irb, python3 and wrapped bash 12/12 — and then failed the suite, because the existing
test child answers `REPLY:ping` to `ping` and the anchor lands inside the answer. It was reverted.
The measurement that looked like a win was real and incomplete, which is the same shape as the 0.8.0
settle fix it was meant to finish.
