---
change: CHG-0061-release-0-9-0-bump-the-version-and-record-the-round-s-measurements
artifact: docs
---

# Docs

The changelog and roadmap are the deliverable here. `AGENTS.md`, `README.md` and
the guides needed no change — `docs-check` gates the version strings and the flag
coverage mechanically, and it passes.

Unrelated to this repository but worth recording where the next reader will find
it: the Claude Code skill at `~/.claude/skills/rune` still describes the 0.2.x
surface and states there is no `send` subcommand. The upstream fix is merged
(CorvidLabs/skills#14, 2026-08-16); an installed copy predating it is stale and
needs re-syncing.
