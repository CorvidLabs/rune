---
change: CHG-0026-touch-cli-spec-md-change-log-to-close-the-stale-gate-for-the-0-3-0-version-bum
artifact: context
---

# Context

CI's `specsync check --stale 1` flagged `specs/cli/cli.spec.md` as one commit behind
`lib/rune/version.rb` (a file it owns) after CHG-0025's version bump, since that change touched
`lib/rune/version.rb` without also touching `cli.spec.md` itself. `CHG-0025` had already been
accepted as `no_spec_change: true` and can't be reopened to add new spec content without breaking
its own recorded scope, so this is a small dedicated follow-up: a Change Log entry only, closing
the staleness gap without claiming any Public API, Invariants, or contract change.
