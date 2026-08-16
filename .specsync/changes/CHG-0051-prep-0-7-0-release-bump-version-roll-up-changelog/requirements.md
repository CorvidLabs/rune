---
change: CHG-0051-prep-0-7-0-release-bump-version-roll-up-changelog
artifact: requirements
---

# Requirements

1. `Rune::VERSION`, `plugin.toml` and `Gemfile.lock` agree at 0.7.0.
2. Unreleased rolls into `[v0.7.0]` with a fresh empty Unreleased above it.
3. The notes state what was measured, including the finding that ships unfixed and why.
4. `fledge lanes run release` passes end to end.
