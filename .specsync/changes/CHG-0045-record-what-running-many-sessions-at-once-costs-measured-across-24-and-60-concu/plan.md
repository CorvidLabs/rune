---
change: CHG-0045-record-what-running-many-sessions-at-once-costs-measured-across-24-and-60-concu
artifact: plan
---

# Plan

1. Start many sessions at once and check the things that could plausibly break: starts, cross-talk,
   `list` accuracy, descriptors, memory, leftovers.
2. Scale up to see whether anything is non-linear.
3. Exercise the unnamed-start race at scale, since its test was a stub.
4. Record the cost, since it turned out to be the only finding.
