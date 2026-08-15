---
change: CHG-0045-record-what-running-many-sessions-at-once-costs-measured-across-24-and-60-concu
artifact: research
---

# Research

Idle children, all sessions started concurrently:

| sessions | resident memory | descriptors | per session |
|----------|-----------------|-------------|-------------|
| 24 | 543 MB | 648 | 23 MB / 27 fds |
| 60 | 1361 MB | 1620 | 23 MB / 27 fds |

Flat per session, and unchanged across rounds of sends — 546MB after three rounds at 24, 1365MB
after two at 60.

Correctness under the same load, across 24 and 60 sessions:

- every start succeeded; 60 started in 2.2s
- every send settled, and every reply carried the identity of the session it was addressed to, so
  nothing crossed wires
- `list` agreed with reality
- no supervisors were left running after stopping
- 30 simultaneous `start` calls with no `--name` for the same tool produced 30 distinct
  codenames and no collisions, which exercises the retry path added for that race against real
  contention rather than a stub
