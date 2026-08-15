---
change: CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job
artifact: tasks
---

# Tasks

- [x] identify the rate-limited API call as the cause
- [x] confirm no fledge action.yml exists to use instead
- [x] pin both Install Fledge steps to a release asset with retries
- [x] verify the pinned URL serves the expected binary
