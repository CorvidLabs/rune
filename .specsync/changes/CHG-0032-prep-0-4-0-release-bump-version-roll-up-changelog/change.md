---
id: CHG-0032-prep-0-4-0-release-bump-version-roll-up-changelog
state: accepted
type: feature
base_commit: a15e73f1943f0c482ed7351f9d6eb546d97ae120
---

# Prep 0.4.0 release: bump version, roll up CHANGELOG

## Intent

Prep 0.4.0 release: bump version, roll up CHANGELOG

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Rune::VERSION and plugin.toml [plugin].version both read 0.4.0; fledge run version-check passes; CHANGELOG.md's Unreleased section is rolled into a new [v0.4.0] - 2026-08-15 section with a fresh empty Unreleased above it; fledge lanes run release (version-check, fmt-check, lint, test, spec-check, spec-lifecycle, smoke-test, build) passes end to end, including a successful gem build.

## No-spec Rationale

Not applicable
