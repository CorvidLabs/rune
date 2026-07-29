---
change: CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and
artifact: testing
---

# Testing

- REQ-001/REQ-002: RSpec fixtures cover one already-current source, one stale source, and a missing pattern without partial writes.
- REQ-003: `specsync change check` and strict contract coverage validate the expanded meaningful paths.
- REQ-004: Workflow assertions require exact `refs/tags/$RELEASE_TAG` validation.
- REQ-005: Workflow assertions require an ancestor check against `origin/main`.
- REQ-006: `fledge lanes run release` and `fledge trust verify --range main..HEAD` remain green.
