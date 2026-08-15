---
change: CHG-0032-prep-0-4-0-release-bump-version-roll-up-changelog
artifact: plan
---

# Plan

1. Bump `Rune::VERSION` and `plugin.toml` together — `version-check` fails if they drift.
2. Roll up the changelog, correcting one stale entry: it described a bash+jq example that was
   converted to Ruby (`examples/agents/cli_envelope.rb`) in the same release, contradicting the
   claim two lines later that no shell scripts remain.
3. Record the settle-default change and the dogfooding fixes, which landed after the Unreleased
   section was first written.
4. Run the release lane.
