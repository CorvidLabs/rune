---
id: CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e
state: archived
type: feature
base_commit: 6a787480056528f918314658b2d359e4d1129024
---

# Fix an attachment reporting both that the session is still running and that it ended, in the same exit

## Intent

Fix an attachment reporting both that the session is still running and that it ended, in the same exit

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A deliberate detach prints the still-running note and exits 0; an attachment that ends because output stopped prints no such note, exits 1, and says what is known rather than asserting that the child or supervisor exited. Verified end to end over a pty on both paths, with no contradictory pair on either. Two of three regression tests fail against the unfixed version. Full suite and lint pass.

## No-spec Rationale

Not applicable
