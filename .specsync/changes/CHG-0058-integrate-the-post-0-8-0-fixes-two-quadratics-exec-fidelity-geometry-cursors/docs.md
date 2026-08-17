---
change: CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors
artifact: docs
---

# Docs

`docs-check` now gates the guides against the CLI: version strings must match and every advertised
flag must be named somewhere. It was added after a stale version string survived three releases and a
flag went undocumented for four, and it was verified to fail on drift rather than only to pass clean.

AGENTS.md was rewritten — it had been instructing agents to use a provenance gate that is off.
`docs/sessions.md` gained the submit race, the per-directory namespacing that made a live session
look dead, and the render window's real cost.
