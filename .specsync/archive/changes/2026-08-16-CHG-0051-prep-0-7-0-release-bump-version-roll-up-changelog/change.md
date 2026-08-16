---
id: CHG-0051-prep-0-7-0-release-bump-version-roll-up-changelog
state: archived
type: feature
base_commit: 9f2bb58db796eff3dea7b4b75f18d4ae1f983664
---

# Prep 0.7.0 release: bump version, roll up CHANGELOG

## Intent

Prep 0.7.0 release: bump version, roll up CHANGELOG

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Rune::VERSION, plugin.toml and Gemfile.lock all read 0.7.0 and version-check agrees. The Unreleased section is rolled into [v0.7.0] with a fresh empty Unreleased above it, and the notes state what was measured rather than what was intended, including the finding that ships unfixed. fledge lanes run release passes end to end and builds rune-0.7.0.gem.

## No-spec Rationale

Not applicable
