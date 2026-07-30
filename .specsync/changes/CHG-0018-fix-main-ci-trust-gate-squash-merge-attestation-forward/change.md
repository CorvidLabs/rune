---
id: CHG-0018-fix-main-ci-trust-gate-squash-merge-attestation-forward
state: accepted
type: bug_fix
base_commit: 1ce1605f71c2e1fac2650feb6df1360927eb14bc
---

# Fix main CI trust gate squash-merge attestation forward

## Intent

Fix main CI trust gate squash-merge attestation forward

## Affected Canonical Specs

- None

## Acceptance Criteria

- Main push Trust gate forwards attestations from every squash-merged PR head (including multi-PR stack pushes) by fetching refs/pull/N/head, then attest verify passes for the push range; unit tests cover the forward-map script; no Rune library API changes.

## No-spec Rationale

CI workflow and helper scripts only; no public library or canonical contract change. Provenance forwarding is infrastructure for the trust gate, not a Rune CLI/API behavior.
