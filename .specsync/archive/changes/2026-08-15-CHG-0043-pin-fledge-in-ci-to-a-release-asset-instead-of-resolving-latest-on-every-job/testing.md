---
change: CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job
artifact: testing
---

# Testing

The workflow parses, and the pinned URL was fetched directly: it returns a 39MB static-pie x86-64
ELF executable, which is what the runners need.

The real test is CI itself — the six Ruby jobs went green on the first run after the pin, having
failed intermittently before it.
