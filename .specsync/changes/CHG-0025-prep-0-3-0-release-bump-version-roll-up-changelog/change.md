---
id: CHG-0025-prep-0-3-0-release-bump-version-roll-up-changelog
state: accepted
type: operations
base_commit: 56588e061d2cf999f55d092bd9e78164f7c85ede
---

# Prep 0.3.0 release: bump version, roll up CHANGELOG

## Intent

Prep 0.3.0 release: bump version, roll up CHANGELOG

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Rune::VERSION and plugin.toml [plugin].version both read 0.3.0; fledge run version-check passes; CHANGELOG.md's Unreleased section is rolled into a new [v0.3.0] - 2026-08-14 section with a fresh empty Unreleased above it; fledge lanes run release (version-check, fmt-check, lint, test, spec-check, spec-lifecycle, smoke-test, build) passes end to end, including a successful gem build.

## No-spec Rationale

Version constant bump and changelog reorganization only; no library code, public API, or canonical contract change.
