---
id: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
state: archived
type: feature
base_commit: fe93c863bda8d91d977ba5d3f66928ea346502b6
---

# Second review round: the regex echo bug fixed, four renderer defects fixed, and one rule disproved

## Intent

Second review round: the regex echo bug fixed, four renderer defects fixed, and one rule disproved

## Affected Canonical Specs

- `parsers`
- `session`
- `cli`

## Acceptance Criteria

- wait-for-regex no longer matches the pty echo: 3/3 wait for real output against python3 where it previously matched the echo in 0.22s, 4/4. RIS and DECSTR reset the scroll region. Private-marker CSI sequences no longer run as their public namesakes. BEL, NUL, SO, SI and DEL no longer occupy cells. An oversize DECSTBM bottom is clamped rather than discarded. The settle path's remaining defect, and the rule that was measured and disproved, are documented rather than guessed at. 411 examples pass, lint clean.

## No-spec Rationale

Not applicable
