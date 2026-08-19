---
id: CHG-0074-correct-the-wait-for-regex-reprint-advice-qualify-reprint-not-visible-histor
state: accepted
type: documentation
base_commit: de4bfa743d3c6a4c97fb4639bd42bfc7be5983f6
---

# Correct the --wait-for-regex reprint advice: qualify reprint, not visible history, and stop pairing child_busy with the unique sentinel

## Intent

Correct the --wait-for-regex reprint advice: qualify reprint, not visible history, and stop pairing child_busy with the unique sentinel

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- English sessions.md, session.spec.md and ROADMAP no longer say 'visible history' or treat child_busy as equivalent to a unique-per-turn sentinel. The lead workaround is a sentinel the child will not reprint; a destination file is the other real check. Spec version is 37 with one CHG-0073 row and one CHG-0074 row.

## No-spec Rationale

Not applicable
