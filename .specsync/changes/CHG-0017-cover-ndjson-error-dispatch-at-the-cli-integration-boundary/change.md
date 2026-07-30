---
id: CHG-0017-cover-ndjson-error-dispatch-at-the-cli-integration-boundary
state: accepted
type: bug_fix
base_commit: 3a9723a09026488b49b516c5fcf6935de587ed17
---

# Cover NDJSON error dispatch at the CLI integration boundary

## Intent

Cover NDJSON error dispatch at the CLI integration boundary

## Affected Canonical Specs

- None

## Acceptance Criteria

- An unknown command invoked with --ndjson emits exactly one parseable stdout line with event error, status error, and the structured unknown-command message; the CLI spec and full suite pass

## No-spec Rationale

This is test-only coverage for the existing canonical CLI contract that NDJSON failures use event error; no canonical behavior changes beyond CHG-0016.
