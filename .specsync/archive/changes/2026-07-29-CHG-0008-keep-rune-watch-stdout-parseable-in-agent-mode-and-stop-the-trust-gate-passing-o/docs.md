---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: docs
---

# Docs

- `README.md`: note under `rune watch` that in agent mode (`--json`, `--ndjson`, or piped stdout)
  the live passthrough moves to stderr so stdout stays a clean structured result. Correct the stale
  "160 examples" figure to the current count.
- `docs/getting_started.md`: show the agent-mode invocation
  (`rune watch --json -- CMD 2>/dev/null | jq`) alongside the existing human example.
- `CHANGELOG.md`: an Unreleased `### Fixed` entry for both defects.
- `docs/releasing.md`: no change needed — step 2 already requires attesting the landed commit; CI
  now enforces what the document already said.
