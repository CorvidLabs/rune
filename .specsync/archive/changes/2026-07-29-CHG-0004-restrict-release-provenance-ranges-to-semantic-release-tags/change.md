---
id: CHG-0004-restrict-release-provenance-ranges-to-semantic-release-tags
state: archived
type: bug_fix
base_commit: 24c591c9b366cb7a6aebb653f7ab9d29a687f00d
---

# Restrict release provenance ranges to semantic release tags

## Intent

Restrict release provenance ranges to semantic release tags

## Affected Canonical Specs

- None

## Acceptance Criteria

- Both publish jobs select the previous tag only from the semantic release-tag convention and regression coverage prevents unrestricted git describe --tags from returning

## No-spec Rationale

The CLI v3 contract already mandates release provenance; this fix narrows prior-tag discovery so that existing invariant cannot be bypassed by unrelated tags
