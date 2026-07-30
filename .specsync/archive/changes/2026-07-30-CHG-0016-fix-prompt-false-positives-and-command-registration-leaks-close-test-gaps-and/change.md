---
id: CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and
state: archived
type: bug_fix
base_commit: 3a9723a09026488b49b516c5fcf6935de587ed17
---

# Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible

## Intent

Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible

## Affected Canonical Specs

- `cli`
- `parsers`
- `watch`

## Acceptance Criteria

- Ordinary output ending in # > $ or % and prose questions do not set prompt_detected; command classes register when their DSL name is declared without persistent TracePoints; NDJSON failures use event error; explicit watch logs are mode 0600; Rune error stdout behavior and dependency locking are documented and tested; strict SpecSync and the full trust gate pass

## No-spec Rationale

Not applicable
