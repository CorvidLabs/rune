---
id: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
state: archived
type: feature
base_commit: b89daa34de393815c5adbbbdf239bc732a51bb90
---

# Rotate a session transcript without reading it: seek to the cut and copy the tail, instead of parsing every line

## Intent

Rotate a session transcript without reading it: seek to the cut and copy the tail, instead of parsing every line

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A transcript rotation costs no measurable memory: 0.1MB against 229MB for the original implementation and 96MB for a streaming-but-still-parsing one. Rotation seeks to the cut point rather than scanning the dropped region, reads the bytes field each event already records rather than parsing events, and copies with IO.copy_stream so bytes never enter Ruby. The accounting stays exact and cursors keep their meaning. Full suite and lint pass.

## No-spec Rationale

Not applicable
