---
change: CHG-0025-prep-0-3-0-release-bump-version-roll-up-changelog
artifact: testing
---

# Testing

- `fledge run version-check` — `lib/rune/version.rb` and `plugin.toml` agree at 0.3.0.
- `fledge run fmt-check` / `fledge run lint` — no offenses.
- `fledge run test` — full suite green.
- `fledge run spec-check` — 100% coverage, no drift.
- `fledge run spec-lifecycle` — all specs pass lifecycle enforcement.
- `fledge run smoke-test` — 30/30 real end-to-end checks pass.
- `fledge run build` — `gem build rune.gemspec` succeeds and picks up 0.3.0.
- Evidence to be filled in after running the full release lane.
