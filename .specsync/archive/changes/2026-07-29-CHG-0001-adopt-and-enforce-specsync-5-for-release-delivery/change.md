---
id: CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery
state: archived
type: migration
base_commit: 196f7789c01d03a3f23769d2bb417553230173ef
---

# Adopt and enforce SpecSync 5 for release delivery

## Intent

Adopt and enforce SpecSync 5 for release delivery

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- A source-only change to a mapped module fails local and CI SpecSync drift gates
- Updating the CLI source and canonical spec together passes strict 100% coverage and lifecycle enforcement
- SpecSync 5 SDD policy rejects meaningful delivery changes not covered by an approved active change
- The release lane, installed gem, trust gate, and strict provenance remain green

## No-spec Rationale

Not applicable
