---
id: CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors
state: archived
type: feature
base_commit: 7041cb9163a91f82075fe50e1be202ceba717a09
---

# Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate

## Intent

Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate

## Affected Canonical Specs

- `cli`
- `parsers`
- `pty_runner`
- `session`
- `watch`

## Acceptance Criteria

- Every path this integration branch changed is covered by a change record, so spec-check passes. The branch carries: two quadratics in the send path removed, a one-element argv array exec'd rather than shelled, screen rendering at the child's real size, transcript cursors mapped through each dropped region, a hard ceiling keeping the transcript bound honest, the submit delay raised so every agent CLI submits, the render window sized against real TUI output, and a docs-check gate. 519 examples pass, lint and docs-check clean.

## No-spec Rationale

Not applicable
