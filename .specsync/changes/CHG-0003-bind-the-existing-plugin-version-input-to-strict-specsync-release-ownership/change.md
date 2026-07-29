---
id: CHG-0003-bind-the-existing-plugin-version-input-to-strict-specsync-release-ownership
state: accepted
type: operations
base_commit: bc21bf21dca0e2458dab2a0c6950031676fd7108
---

# Bind the existing plugin version input to strict SpecSync release ownership

## Intent

Bind the existing plugin version input to strict SpecSync release ownership

## Affected Canonical Specs

- None

## Acceptance Criteria

- Strict SpecSync verification recognizes plugin.toml as covered by an approved change and the full trust gate passes without weakening meaningful_paths

## No-spec Rationale

The CLI v3 invariant already specifies plugin.toml version parity; this change records ownership for the existing release bump without altering canonical behavior
