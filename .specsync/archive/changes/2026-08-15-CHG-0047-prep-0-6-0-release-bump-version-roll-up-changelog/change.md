---
id: CHG-0047-prep-0-6-0-release-bump-version-roll-up-changelog
state: archived
type: feature
base_commit: 928c6c31aabc4f5992fe7175daefecaf92e9ec94
---

# Prep 0.6.0 release: bump version, roll up CHANGELOG

## Intent

Prep 0.6.0 release: bump version, roll up CHANGELOG

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Rune::VERSION and plugin.toml [plugin].version both read 0.6.0; fledge run version-check passes; CHANGELOG.md's Unreleased section is rolled into a new [v0.6.0] - 2026-08-15 section with a fresh empty Unreleased above it; fledge lanes run release passes end to end including a successful gem build.

## No-spec Rationale

Not applicable
