---
id: CHG-0013-finalize-commit-anchored-exact-cli-spec-coverage-for-the-accepted-help-stack
state: archived
type: operations
base_commit: bf384e40f45bbf7e8eb1c3d3f09b00af137b91d3
---

# Finalize commit-anchored exact CLI spec coverage for the accepted help stack

## Intent

Finalize commit-anchored exact CLI spec coverage for the accepted help stack

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- 1. The exact CLI spec path is anchored to commit bf384e4, which contains all accepted predecessor evidence. 2. The canonical CLI contract is unchanged. 3. Strict SpecSync and the unified trust gate pass with no stale evidence.

## No-spec Rationale

The accepted semantic contract is committed at bf384e4; this exact-path successor anchors its delivery coverage to that commit without changing the canonical spec.
