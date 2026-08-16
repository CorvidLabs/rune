---
id: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
state: accepted
type: feature
base_commit: 896813d4a8029c914d0b40ad5d3638a8cd364526
---

# Extract the transcript out of SessionCommand: reconstruction, cursors, search and rendering are one subject

## Intent

Extract the transcript out of SessionCommand: reconstruction, cursors, search and rendering are one subject

## Affected Canonical Specs

- `session`
- `cli`

## Acceptance Criteria

- Session::Transcript owns reading the NDJSON log, cursor arithmetic across rotation, search and screen rendering, and is exercised without constructing a SessionCommand. session_command.rb drops from 930 to about 853 lines. Behaviour is unchanged: the full suite passes, including every regression test for rotation accounting and grep.

## No-spec Rationale

Not applicable
