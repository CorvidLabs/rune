---
id: CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job
state: accepted
type: feature
base_commit: 7789240d5b70dec0b981dbaddfcb68ae85fa3401
---

# Pin fledge in CI to a release asset instead of resolving latest on every job

## Intent

Pin fledge in CI to a release asset instead of resolving latest on every job

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- Both CI jobs install fledge by downloading a pinned release asset directly, making no GitHub API call, with retries for ordinary network flake. The six Ruby jobs and Spec Sync stop failing intermittently with 'could not determine latest version'. No library, spec, or contract content changes.

## No-spec Rationale

Not applicable
