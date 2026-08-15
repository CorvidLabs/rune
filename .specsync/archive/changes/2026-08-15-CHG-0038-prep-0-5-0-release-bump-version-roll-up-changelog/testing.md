---
change: CHG-0038-prep-0-5-0-release-bump-version-roll-up-changelog
artifact: testing
---

# Testing

`fledge run version-check` pins `Rune::VERSION` against `plugin.toml` so the two cannot drift.
`fledge lanes run release` covers version-check, fmt-check, lint, test, spec-check, spec-lifecycle,
smoke-test and build; the build step proves the gem packages at this version.

No behavior change here, so no new examples.
