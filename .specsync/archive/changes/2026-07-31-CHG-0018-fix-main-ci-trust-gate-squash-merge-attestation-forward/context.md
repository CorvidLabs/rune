---
change: CHG-0018-fix-main-ci-trust-gate-squash-merge-attestation-forward
artifact: context
---

# Context

Main-branch push CI fails the Trust gate after squash-merge. Attest tries to
forward provenance from the reviewed PR head to the landed squash commit, but a
checkout of `main` does not contain the PR-head object (`Unknown revision`).
Multi-PR stack merges land several squash commits in one push; the previous
workflow only forwarded the tip, leaving intermediate commits unattested.

This change is CI/infrastructure only: workflow + helper script + unit tests.
No Rune library or canonical-spec contract changes.
