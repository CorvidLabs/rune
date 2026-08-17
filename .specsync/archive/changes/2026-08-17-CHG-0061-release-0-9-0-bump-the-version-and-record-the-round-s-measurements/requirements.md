---
change: CHG-0061-release-0-9-0-bump-the-version-and-record-the-round-s-measurements
artifact: requirements
---

# Requirements

1. `Rune::VERSION`, `plugin.toml`, `Gemfile.lock` and `docs/getting_started.md`
   agree on 0.9.0. The `docs-check` gate fails the build otherwise, which is why
   a guide version is in scope for a release commit at all.
2. `CHANGELOG` gains a dated 0.9.0 heading and this round's entries.
3. `ROADMAP` reflects measurement, not history.
4. The full release lane passes.
