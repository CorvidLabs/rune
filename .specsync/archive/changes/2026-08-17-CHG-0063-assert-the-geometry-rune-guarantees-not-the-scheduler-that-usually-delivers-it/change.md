---
id: CHG-0063-assert-the-geometry-rune-guarantees-not-the-scheduler-that-usually-delivers-it
state: archived
type: feature
base_commit: ffa04d03e4ce1f5593018372a17545019cc7de72
---

# Assert the geometry rune guarantees, not the scheduler that usually delivers it

## Intent

Assert the geometry rune guarantees, not the scheduler that usually delivers it

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- The two terminal-size specs assert that the child ends up at the documented default, by either the startup read or the SIGWINCH that follows, instead of asserting that the startup read won a race it does not always win. session.spec.md invariant 49a records why the race exists and what closing it would cost. The suite passes on every supported Ruby in CI.

## No-spec Rationale

Not applicable
