---
change: CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job
artifact: plan
---

# Plan

1. Establish why the installer fails, rather than retrying until it passes.
2. Check for a marketplace action first.
3. Download the pinned release asset directly in both jobs, since the script offers no version
   variable.
