---
id: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
state: archived
type: feature
base_commit: 932b3f628d81cffe48901eb619b0af33189f36e9
---

# Bound the supervisor's in-memory transcript to a window, so a persistent session's resident memory stops tracking output one-for-one

## Intent

Bound the supervisor's in-memory transcript to a window, so a persistent session's resident memory stops tracking output one-for-one

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- The supervisor holds a bounded window of output rather than every byte the child has produced, while cursors stay absolute offsets into the whole stream and never trim past a live send. Measured against a child emitting 500KB/s: before, resident memory tracked output one-for-one, 27MB to 69MB in eighty seconds, never coming down; after, it plateaus, with the last 60 seconds of a 150-second run adding 30MB of output and 0.16MB of memory. Three regression tests, two of which fail against the unbounded version. Full suite and lint pass.

## No-spec Rationale

Not applicable
