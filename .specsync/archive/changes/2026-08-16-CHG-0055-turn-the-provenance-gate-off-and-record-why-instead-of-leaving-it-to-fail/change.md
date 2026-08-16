---
id: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
state: archived
type: feature
base_commit: bc30c64da1284057e09a48320ba99cac1b33d737
---

# Turn the provenance gate off, and record why, instead of leaving it to fail

## Intent

Turn the provenance gate off, and record why, instead of leaving it to fail

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- The release lane no longer runs a provenance check and passes end to end without any signing step. The publish workflow no longer references attest, while its tag and version validation is untouched. .trust.toml records provenance.mode = off with a stated reason, so the state is declared rather than implicit. docs/releasing.md, README and CHANGELOG match. Tests that asserted on the removed steps are retargeted rather than deleted.

## No-spec Rationale

Not applicable
