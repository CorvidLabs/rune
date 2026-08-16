---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: research
---

# Research

| release | publish result | cause |
|---|---|---|
| v0.4.0 | failure, 12s | provenance, unnoticed |
| v0.5.0 | failure, 15s | provenance, unnoticed |
| v0.6.0 | failure, 15s | provenance, unnoticed |
| v0.7.0 | not attempted | tagged manually |
| v0.8.0 | blocked | provenance, in the release lane |

Attest notes stop at `a5bfcfd` (2026-08-14), so no commit since has one. `fledge trust doctor`
accepts `mode = "off"` and rejects it without a reason, which is why the reason is where it is.

The lane confirms the change: it previously failed at step 2 in 1.6s, and now reaches step 5.
