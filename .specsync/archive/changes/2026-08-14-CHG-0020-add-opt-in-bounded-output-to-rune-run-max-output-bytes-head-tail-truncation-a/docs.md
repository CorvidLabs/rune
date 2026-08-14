---
change: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
artifact: docs
---

# Docs

- `specs/pty_runner/pty_runner.spec.md` is the canonical contract update (Public API, Invariants,
  Behavioral Examples, Error Cases, Change Log) — done in the same change as the code per
  `AGENTS.md`.
- README's `rune run --help` example output already documents flags generically via the `flag`
  DSL (`rune run --help --json`), so `--max-output`/`--tail` become discoverable there
  automatically once declared — no separate README edit required.
- `CHANGELOG.md` `[Unreleased]` gets an `Added` entry for both flags.
