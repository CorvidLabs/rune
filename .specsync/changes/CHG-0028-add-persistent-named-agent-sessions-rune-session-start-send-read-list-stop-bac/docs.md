---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: docs
---

# Docs

- New canonical spec `specs/session/session.spec.md` (Purpose / Public API / Invariants /
  Behavioral Examples / Error Cases / Dependencies / Change Log), matching the house format used by
  `specs/watch/watch.spec.md`.
- New `docs/sessions.md`: the agent-driving-agent loop end to end, with **real captured output**
  (the convention `docs/getting_started.md` already follows), plus an explicit section on settle
  semantics and their limits — `--settle-ms` is a heuristic, `--wait-for-regex` is the
  deterministic option, `prompt_detected` is advisory and usually `false` for agent CLIs.
- `README.md` link to the new page alongside the existing getting-started link.
- CHANGELOG `[Unreleased] / Added` entry.
- `rune session --help` and per-subcommand help are themselves user-facing docs, generated from the
  `usage`/`flag` DSL so they cannot drift from the parser.
