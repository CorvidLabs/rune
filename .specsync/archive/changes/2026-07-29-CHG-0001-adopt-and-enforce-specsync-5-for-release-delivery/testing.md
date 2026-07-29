---
change: CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery
artifact: testing
---

# Testing

Acceptance evidence:

- Negative control: temporarily change `lib/rune/version.rb` without its canonical spec and confirm
  `specsync check --force --strict --stale 1 --require-coverage 100` exits non-zero with CLI drift.
- Positive control: restore the source, apply the approved CLI delta, and confirm the same command
  exits zero.
- Run `specsync lifecycle enforce --all` and `specsync change check`.
- Run `fledge lanes run release` for version parity, lint, 163+ RSpec examples, strict SpecSync,
  30 smoke checks, and gem build.
- Install the built gem into an isolated gem home and confirm `rune version --json` reports 0.2.1.
- Run `fledge trust verify --range main..HEAD` and strict Attest verification for
  `v0.2.0..HEAD`.
- Require the complete Ruby 3.0–4.0, CodeQL, and trust matrix on PR #5.
