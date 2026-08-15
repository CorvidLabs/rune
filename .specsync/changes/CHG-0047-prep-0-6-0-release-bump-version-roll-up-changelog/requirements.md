---
change: CHG-0047-prep-0-6-0-release-bump-version-roll-up-changelog
artifact: requirements
---

# Requirements

1. `Rune::VERSION` and `plugin.toml` both read 0.6.0, with `Gemfile.lock` following.
2. The Unreleased section rolls into `[v0.6.0] - 2026-08-15` with a fresh empty Unreleased above.
3. The notes say what each fix cost in figures, since most of them were found by measurement and the
   numbers are the evidence.
