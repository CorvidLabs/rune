---
change: CHG-0004-restrict-release-provenance-ranges-to-semantic-release-tags
artifact: design
---

# Design

Define the release-tag pattern once per publish job and pass it to `git describe --match`. The accepted release format is `vMAJOR.MINOR.PATCH`, so prior-tag candidates must match `v[0-9]*.[0-9]*.[0-9]*`. Preserve the exact-tag, checked-out-commit, mainline ancestry, version-parity, and Attest checks already present.
