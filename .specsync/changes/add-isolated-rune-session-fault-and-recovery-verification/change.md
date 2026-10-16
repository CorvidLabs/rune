---
id: add-isolated-rune-session-fault-and-recovery-verification
state: draft
type: refactor
base_commit: 252702cf4d355076b9a4d2533e1d506aad3b0f02
---

# Add isolated Rune session fault and recovery verification

## Intent

Add isolated Rune session fault and recovery verification

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- Agent-proposed checks: isolated fixtures exercise existing failure and recovery behavior; all new assertions reject corresponding deliberate faults; missing process identities never signal; unresolved cleanup preserves evidence and fails; complete existing tests pass without library changes.

## No-spec Rationale

Not applicable
