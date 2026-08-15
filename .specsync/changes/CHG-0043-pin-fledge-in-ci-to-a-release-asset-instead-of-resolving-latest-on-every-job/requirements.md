---
change: CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job
artifact: requirements
---

# Requirements

1. Installing fledge must not depend on a rate-limited API call.
2. The version must be pinned, so a CI run is reproducible.
3. Ordinary network flake should be retried rather than failing the job.
