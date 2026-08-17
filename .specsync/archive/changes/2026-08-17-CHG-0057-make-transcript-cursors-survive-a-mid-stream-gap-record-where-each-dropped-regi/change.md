---
id: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
state: archived
type: bug_fix
base_commit: 75fb0141d5eac0a757cd000f4b1ed994178b52cf
---

# Make transcript cursors survive a mid-stream gap: record where each dropped region sits and map cursors through the list

## Intent

Make transcript cursors survive a mid-stream gap: record where each dropped region sits and map cursors through the list

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A cursor issued before a mid-stream gap resolves to the output that followed it, never to output already delivered: measured on 25x4000B, a 48000-byte gap and 25 more, from(100000) returned 148000 bytes (48000 replayed) before and 100000 after, and every probe before/inside/after every gap matches an independent oracle. A single prefix gap collapses to exactly the old arithmetic at every probe. A failed transcript write is carried and recorded as a truncated event by the next write that succeeds. Rotation counts what the reader parses: +400000/-4096/-16384/-40960/+16384 bytes of cursor skew before, 0 in all five cases after. 488 examples pass, lint clean.

## No-spec Rationale

Not applicable
