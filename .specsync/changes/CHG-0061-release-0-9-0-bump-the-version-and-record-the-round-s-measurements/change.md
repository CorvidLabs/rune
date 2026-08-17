---
id: CHG-0061-release-0-9-0-bump-the-version-and-record-the-round-s-measurements
state: accepted
type: feature
base_commit: 7041cb9163a91f82075fe50e1be202ceba717a09
---

# Release 0.9.0: bump the version and record the round's measurements

## Intent

Release 0.9.0: bump the version and record the round's measurements

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Rune::VERSION, plugin.toml, Gemfile.lock and docs/getting_started.md all read 0.9.0 and agree, which the docs-check gate enforces for the guide. CHANGELOG's Unreleased section becomes v0.9.0 dated 2026-08-17 and gains entries for the two fixes made this round plus a Verified-not-changed section for the two durability claims that were observed rather than altered. ROADMAP's 0.8.0 review table is re-measured against the tree: seven of eight closed, one corrected because measurement contradicted it, one left open. The full release lane passes.

## No-spec Rationale

Not applicable
