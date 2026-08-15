---
id: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
state: accepted
type: feature
base_commit: e73c3d5d3a69214c2e862dc97686e2a018a8df9e
---

# Bound a --wait-for-regex match so a catastrophically backtracking pattern cannot wedge the supervisor past its own timeout

## Intent

Bound a --wait-for-regex match so a catastrophically backtracking pattern cannot wedge the supervisor past its own timeout

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A --wait-for-regex pattern that backtracks catastrophically is abandoned with regex_timed_out: true rather than blocking the event loop, the send returns well inside its --timeout-ms, and the session remains usable afterwards. Verified end to end with a backreference pattern against a child emitting 60 a characters: the send previously blocked long past its 8s deadline and now returns in under a second. Regression tests fail against the unfixed code and pass against the fix, and skip on Ruby below 3.2 where no per-Regexp timeout exists. Full suite and lint pass.

## No-spec Rationale

Not applicable
