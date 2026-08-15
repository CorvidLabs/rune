---
id: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
state: accepted
type: feature
base_commit: 846b0f4516b36abdeb6cdeba1824f7efd0aebbdd
---

# Report child_busy and idle_ms on read, and document that exit_code is a process status rather than a verdict on the work

## Intent

Report child_busy and idle_ms on read, and document that exit_code is a process status rather than a verdict on the work

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- rune session read reports child_busy and idle_ms, derived from the transcript's own timestamps so they work for a stopped session, and verified to be true at 61ms idle and false at 3268ms. The getting-started guide states that exit_code means the wrapped process ended rather than that the work succeeded, with the observed case of eight consecutive zero exits from runs whose conclusions were wrong. The session guide notes that child_busy means the child is printing, not that it is working. Full suite and lint pass.

## No-spec Rationale

Not applicable
