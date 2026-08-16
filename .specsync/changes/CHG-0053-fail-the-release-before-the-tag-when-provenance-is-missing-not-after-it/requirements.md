---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: requirements
---

# Requirements

1. A release must stop before the tag when any commit since the previous release tag lacks an
   attestation.
2. The failure must name the command that fixes it, not only report the state.
3. The check must fail, never pass, when it could not run: no attest installed, or no previous
   release tag.
