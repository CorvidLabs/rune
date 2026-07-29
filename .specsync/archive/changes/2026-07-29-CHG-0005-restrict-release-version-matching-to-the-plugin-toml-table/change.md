---
id: CHG-0005-restrict-release-version-matching-to-the-plugin-toml-table
state: archived
type: bug_fix
base_commit: dd3a968da0fca38384f9dee153a0e142007409fa
---

# Restrict release version matching to the plugin TOML table

## Intent

Restrict release version matching to the plugin TOML table

## Affected Canonical Specs

- None

## Acceptance Criteria

- The setter and release checker reject a plugin table without its own version even when a later table defines version and neither file is partially rewritten

## No-spec Rationale

The CLI v3 contract already requires plugin version parity; this fix makes the existing invariant reject malformed manifests instead of reading another table
