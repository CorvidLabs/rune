---
change: CHG-0032-prep-0-4-0-release-bump-version-roll-up-changelog
artifact: testing
---

# Testing

`fledge run version-check` pins `Rune::VERSION` against `plugin.toml`, so the two cannot drift.
`fledge lanes run release` covers version-check, fmt-check, lint, test, spec-check, spec-lifecycle,
smoke-test and build; the build step is what proves the gem actually packages at this version.

No new behavior, so no new examples.
