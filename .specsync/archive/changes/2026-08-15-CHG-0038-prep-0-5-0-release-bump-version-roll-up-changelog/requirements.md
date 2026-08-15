---
change: CHG-0038-prep-0-5-0-release-bump-version-roll-up-changelog
artifact: requirements
---

# Requirements

1. `Rune::VERSION` and `plugin.toml` both read 0.5.0, with `Gemfile.lock` following.
2. The Unreleased section rolls into `[v0.5.0] - 2026-08-15` with a fresh empty Unreleased above.
3. The release notes state plainly that 0.4.0 is broken for its primary use case.
4. The 0.4.0 settle figures are corrected in the notes, not silently replaced.
