---
change: CHG-0018-fix-main-ci-trust-gate-squash-merge-attestation-forward
artifact: tasks
---

# Tasks

- [x] Add `scripts/squash_attest_forwards.sh` to emit PR-head → landed TSV rows
- [x] Update `.github/workflows/ci.yml` to fetch PR heads and forward all pairs
- [x] Unit-test the forward-map script
- [x] Backfill notes on already-landed main squash commits
- [x] Open PR and pass local trust verify
