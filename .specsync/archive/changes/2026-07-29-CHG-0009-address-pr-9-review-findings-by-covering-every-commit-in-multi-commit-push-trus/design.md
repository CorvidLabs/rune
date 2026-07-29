---
change: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
artifact: design
---

# Design

## Push trust ranges

The CI range-resolution step distinguishes supported event types explicitly:

- Pull requests retain `origin/main..HEAD`.
- Pushes call `scripts/trust_range.sh` with `TRUST_PUSH_BEFORE_SHA` and
  `TRUST_PUSH_AFTER_SHA` from the event payload.
- Any other event fails rather than guessing.

The script requires both push boundaries together, verifies both commits exist, rejects GitHub's
all-zero initial-push sentinel, and applies the existing non-empty count guard. A direct
multi-commit push therefore sends the entire `${before}..${after}` range to Augur and Attest.
Local callers without event boundaries retain the existing feature-branch and main fallback logic.

Squash-merge provenance forwarding remains tip-specific. Earlier commits in a multi-commit direct
push must carry their own attestations and are now included in strict verification.

## PTY-optional E2E loading

`spec_helper` loads Rune, whose PTY runner already conditionally requires `pty` and records a
`LoadError`. The E2E file removes its redundant unconditional require. The `rune run` example joins
the existing watch examples in skipping only when PTY is unavailable; version and command-inventory
coverage still executes.

A subprocess regression test places a deterministic failing `pty.rb` first on Ruby's load path and
runs the real E2E file. This exercises the same boot path as an installation where the extension is
absent without adding a test-only production switch.
