---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: plan
---

# Plan

1. Set `provenance.mode = "off"` with the reason, using the toolchain's own switch.
2. Remove the lane check and its script, and the attest steps from both publish jobs.
3. Retarget the tests that asserted on the removed steps, rather than deleting them.
4. Bring the guide, README and CHANGELOG into line.
