---
id: CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic
state: archived
type: feature
base_commit: 45e5df15e718203d4e986efd2687e3ca33eac263
---

# Restore the send settle default to 800ms and correct the 0.4.0 measurement, which was confounded by unsubmitted prompts and by searching a repaint-fragmented byte stream

## Intent

Restore the send settle default to 800ms and correct the 0.4.0 measurement, which was confounded by unsubmitted prompts and by searching a repaint-fragmented byte stream

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- DEFAULT_SETTLE_MS is 800 again and the --settle-ms help text says so. The session spec records the corrected measurement, that the 0.4.0 figures were confounded by two harness faults, and what the new evidence does not cover. Re-measured with both faults fixed and detection on the rendered screen: 27/27 correct claude turns and 18/18 correct grok turns, at every window including 800ms, with the longer window costing up to double the latency per call and buying nothing. Full suite and lint pass.

## No-spec Rationale

Not applicable
