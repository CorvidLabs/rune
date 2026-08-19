---
id: CHG-0073-record-that-wait-for-regex-can-match-a-prior-turn-redraw-and-bring-the-1-0-ro
state: accepted
type: documentation
base_commit: 338ca5a348f3b4eb3257d320408d35d5001125f9
---

# Record that --wait-for-regex can match a prior-turn redraw, and bring the 1.0 roadmap up to date

## Intent

Record that --wait-for-regex can match a prior-turn redraw, and bring the 1.0 roadmap up to date

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- docs/sessions.md and session.spec.md no longer call --wait-for-regex deterministic without the prior-turn-redraw caveat. The caveat is measured on current main: send2 of DONE \d+ against a reprinting child returns in 0.56s with only DONE 1. Two candidate fixes are recorded as rejected (string-novelty loses a second echo DONE; CSI-home veto loses a TUI that paints a reused sentinel with cursor motion). Unique-per-turn sentinels still wait through the reprint (one PendingSend example). ROADMAP no longer lists the renderer as open, and moves the unreproduced half-painted --screen off the 1.0 blocker list.

## No-spec Rationale

Not applicable
