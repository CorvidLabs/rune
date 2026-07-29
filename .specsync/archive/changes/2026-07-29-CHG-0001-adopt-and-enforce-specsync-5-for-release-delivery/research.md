---
change: CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery
artifact: research
---

# Research

Observed behavior with SpecSync 5.2.0:

- `--force` bypasses the hash cache; it does not calculate source/spec drift.
- `--strict` promotes calculated warnings and implies strict enforcement.
- `--require-coverage 100` verifies that source files are assigned to specs, not that spec prose was
  updated after a source change.
- Git drift is opt-in through `--stale N`. The threshold is inclusive, so `--stale 1` blocks a spec
  one or more commits behind while allowing synchronized files at zero.
- The GitHub Action exposes extra check flags through its `args` input and lifecycle checks through
  `lifecycle-enforce`.
- `specsync change check` reported `enabled: false` before adoption.

The negative control `specsync check --force --strict --stale 1 --require-coverage 100` correctly
failed and named `specs/cli/cli.spec.md` as one commit behind `lib/rune/version.rb`.
