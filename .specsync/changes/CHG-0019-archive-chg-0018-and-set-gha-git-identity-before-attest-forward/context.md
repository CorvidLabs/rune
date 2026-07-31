---
change: CHG-0019-archive-chg-0018-and-set-gha-git-identity-before-attest-forward
artifact: context
---

# Context

#27 fixed PR-head fetch for squash-merge attestation forward. The next main
push failed because `git notes add` (used by `attest forward`) requires a git
author identity and GitHub-hosted runners have none. Also archive delivered
CHG-0018 now that its code is on main.
