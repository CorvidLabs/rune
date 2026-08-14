---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: docs
---

# Docs

- `specs/pty_runner/pty_runner.spec.md` is the canonical contract update (Public API, Invariants,
  Behavioral Examples, Error Cases, Change Log) — done in the same change as the code per
  `AGENTS.md`.
- `rune run --help --json` documents `--separate-streams` automatically via the existing `flag`
  DSL — no separate README edit required.
- `CHANGELOG.md` `[Unreleased]` gets an `Added` entry.
