---
change: CHG-0025-prep-0-3-0-release-bump-version-roll-up-changelog
artifact: context
---

# Context

Everything merged to `main` since `v0.2.1` (four opt-in flags across `rune run`/`rune watch`,
one bug fix to `prompt_detected`, one transitive dependency bump) is backward-compatible — no
breaking changes to the CLI surface or the JSON result envelope. Per semver that's a minor bump:
`0.3.0`, not a patch.

This change is prep only: version constant + changelog. Tagging, publishing the gem, and the
downstream `CorvidLabs/homebrew-tap` formula update are deliberately out of scope here, per an
explicit decision to keep the outward-facing publish step separate from this PR.
