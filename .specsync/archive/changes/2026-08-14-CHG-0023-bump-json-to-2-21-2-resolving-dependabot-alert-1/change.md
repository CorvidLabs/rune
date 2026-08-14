---
id: CHG-0023-bump-json-to-2-21-2-resolving-dependabot-alert-1
state: archived
type: operations
base_commit: bb89221130e4fd18c63a56b59abd02ad67aec04b
---

# Bump json to 2.21.2, resolving Dependabot alert #1

## Intent

Bump json to 2.21.2, resolving Dependabot alert #1

## Affected Canonical Specs

- None

## Acceptance Criteria

- Gemfile.lock pins json to 2.21.2 (was 2.21.1, the vulnerable version resolved by Dependabot alert #1); bundle check, fledge run lint, and fledge run test all pass; no library code or canonical spec changes.

## No-spec Rationale

Dependency lockfile-only version bump (transitive rubocop dep); no library code or canonical contract change.
