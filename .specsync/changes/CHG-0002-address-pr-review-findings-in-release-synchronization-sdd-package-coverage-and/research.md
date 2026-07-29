---
change: CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and
artifact: research
---

# Research

- `String#sub` returns content equal to the input both when no pattern matches and when the matched replacement is already present; equality cannot distinguish those cases.
- `git show-ref --verify refs/tags/<name>` distinguishes an exact tag from a branch with the same name.
- `git merge-base --is-ancestor <tag> origin/main` fails when the tag commit is not part of the publishable mainline.
- The repository uses `spec/`, not the generic `tests/` path currently present in the adopted SDD defaults.
