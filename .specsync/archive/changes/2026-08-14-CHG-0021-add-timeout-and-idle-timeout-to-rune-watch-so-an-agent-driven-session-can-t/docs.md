---
change: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
artifact: docs
---

# Docs

- `specs/watch/watch.spec.md` is the canonical contract update (Public API, Invariants, Behavioral
  Examples, Error Cases, Change Log) — done in the same change as the code per `AGENTS.md`.
- `rune watch --help --json` documents both new flags automatically via the existing `flag` DSL,
  same as `RunCommand`'s `--max-output`/`--tail` — no separate README edit required.
- `CHANGELOG.md` `[Unreleased]` gets an `Added` entry for both flags.
