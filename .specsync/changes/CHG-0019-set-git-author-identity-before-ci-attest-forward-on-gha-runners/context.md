---
change: CHG-0019-set-git-author-identity-before-ci-attest-forward-on-gha-runners
artifact: context
---

# Context

After #27 fixed PR-head fetch for squash-merge attestation forward, main CI
failed on the next error: `git notes add` (used by `attest forward`) requires
an author identity, and GitHub-hosted runners have none configured.
