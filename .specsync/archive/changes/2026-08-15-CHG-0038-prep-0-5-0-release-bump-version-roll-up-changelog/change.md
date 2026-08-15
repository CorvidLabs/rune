---
id: CHG-0038-prep-0-5-0-release-bump-version-roll-up-changelog
state: archived
type: feature
base_commit: 4e9651075394e2e617936e6c0d3de2f238a88dbc
---

# Prep 0.5.0 release: bump version, roll up CHANGELOG

## Intent

Prep 0.5.0 release: bump version, roll up CHANGELOG

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Rune::VERSION and plugin.toml [plugin].version both read 0.5.0; fledge run version-check passes; CHANGELOG.md's Unreleased section is rolled into a new [v0.5.0] - 2026-08-15 section with a fresh empty Unreleased above it; fledge lanes run release passes end to end including a successful gem build.

## No-spec Rationale

Not applicable
