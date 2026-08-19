---
id: CHG-0076-correct-the-max-canon-claims-an-unterminated-1024-byte-line-wedges-the-session
state: accepted
type: bug_fix
base_commit: 3519564286fe65de77906a23a5fc3bdfdbf74bfe
---

# Correct the MAX_CANON claims: an unterminated 1024-byte line wedges the session, and raw-mode children are not exempt

## Intent

Correct the MAX_CANON claims: an unterminated 1024-byte line wedges the session, and raw-mode children are not exempt

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- ROADMAP.md, docs/sessions.md and specs/session/session.spec.md all state the same measured behaviour: the limit is 1024 bytes per canonical line including the terminator rune appends (payload budget 1023); crossing it wedges the session for all subsequent input rather than losing one line; every reply during the wedge reports status ok, settled true, state running; VKILL recovers and EOT does not; the discriminator is the tty ICANON state when the bytes land, so raw-mode children are not categorically exempt because bash and python3 are cooked while a foreground command runs; the trigger is an unterminated canonical line reaching 1024 bytes however it was accumulated; and no reply field or BEL heuristic reliably detects it. No document still claims the loss is confined to one line or that raw-mode children are unaffected.

## No-spec Rationale

Not applicable
