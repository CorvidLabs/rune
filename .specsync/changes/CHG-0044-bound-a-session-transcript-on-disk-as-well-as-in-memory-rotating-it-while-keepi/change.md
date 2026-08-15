---
id: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
state: accepted
type: feature
base_commit: 20179ed9ab0f05489c58449a1881dc565cc01ad4
---

# Bound a session transcript on disk as well as in memory, rotating it while keeping cursors absolute

## Intent

Bound a session transcript on disk as well as in memory, rotating it while keeping cursors absolute

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A session's transcript file stays under a ceiling however long the session runs, rotation keeps the recent tail, and every dropped byte is accounted for in a truncated event so cursors stay absolute. A cursor taken after a rotation resolves exactly; one from before it returns what is still held, with dropped_bytes in the reply. Measured: 40MB of output leaves a 16MB file with a 32MB peak, and dropped plus retained equals written exactly. Four regression tests, all failing against the unbounded version. Full suite and lint pass.

## No-spec Rationale

Not applicable
