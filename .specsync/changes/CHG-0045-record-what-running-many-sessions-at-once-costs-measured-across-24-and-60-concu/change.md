---
id: CHG-0045-record-what-running-many-sessions-at-once-costs-measured-across-24-and-60-concu
state: accepted
type: feature
base_commit: 67222d94b486f2318658402340da04c598ea1199
---

# Record what running many sessions at once costs, measured across 24 and 60 concurrent supervisors

## Intent

Record what running many sessions at once costs, measured across 24 and 60 concurrent supervisors

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- The session spec and guide state the measured per-session cost — about 23MB and 27 descriptors, flat at 24 and at 60 concurrent sessions — and that concurrency itself held: 60 simultaneous starts succeeded, every send reached its own session, list agreed with reality, nothing was left running, and 30 simultaneous unnamed starts of one tool produced 30 distinct codenames with no collisions. No behaviour change.

## No-spec Rationale

Not applicable
