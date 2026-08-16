---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: plan
---

# Plan

1. Add `provenance-check` and put it in the release lane, early.
2. Make every could-not-run path a loud failure, and give each one the remedy.
3. Reorder `docs/releasing.md`: sign the merge commit before running the lane, because the squash
   merge produced a commit that has never been attested.
