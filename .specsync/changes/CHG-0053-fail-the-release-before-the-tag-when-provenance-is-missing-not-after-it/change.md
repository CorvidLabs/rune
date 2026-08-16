---
id: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
state: accepted
type: feature
base_commit: 33094e86b6d510722a50554436053a29bbfeb998
---

# Fail the release before the tag when provenance is missing, not after it

## Intent

Fail the release before the tag when provenance is missing, not after it

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- fledge lanes run release fails when any commit since the previous release tag lacks an attestation, and the failure names the command that fixes it. The check fails rather than passes when attest is not installed or when no previous release tag exists. docs/releasing.md orders signing before the lane, since a squash merge produces an unattested commit and the old ordering would fail the first step.

## No-spec Rationale

Not applicable
