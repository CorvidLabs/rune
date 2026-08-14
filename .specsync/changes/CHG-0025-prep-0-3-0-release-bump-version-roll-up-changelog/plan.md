---
change: CHG-0025-prep-0-3-0-release-bump-version-roll-up-changelog
artifact: plan
---

# Plan

1. `ruby scripts/set_release_version.rb 0.3.0` — updates `lib/rune/version.rb` and
   `plugin.toml` together (the same script `fledge run set-version` wraps).
2. `CHANGELOG.md`: rename `## [Unreleased]` to `## [v0.3.0] - 2026-08-14`, add a fresh empty
   `## [Unreleased]` above it, matching the existing `v0.2.1`/`v0.2.0` section format.
3. `fledge lanes run release` (version-check, fmt-check, lint, test, spec-check,
   spec-lifecycle, smoke-test, build) — the full release gate, including the gem build step
   `fledge lanes run verify` doesn't cover.
