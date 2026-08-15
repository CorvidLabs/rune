---
change: CHG-0032-prep-0-4-0-release-bump-version-roll-up-changelog
artifact: requirements
---

# Requirements

1. `Rune::VERSION` reads `0.4.0`.
2. `plugin.toml` `[plugin].version` reads `0.4.0`, matching it.
3. `CHANGELOG.md` rolls the Unreleased section into `[v0.4.0] - 2026-08-15`, leaving a fresh empty
   Unreleased above it.
4. The release lane passes end to end, including a successful gem build.
