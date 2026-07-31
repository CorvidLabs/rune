---
id: CHG-0019-archive-chg-0018-and-set-gha-git-identity-before-attest-forward
state: accepted
type: bug_fix
base_commit: c6aa0fee4ce742207ab5de2dd4fa7e82971051d6
---

# Archive CHG-0018 and set GHA git identity before attest forward

## Intent

Archive CHG-0018 and set GHA git identity before attest forward

## Affected Canonical Specs

- None

## Acceptance Criteria

- CHG-0018 is archived; main push Trust gate sets git author identity and completes attest forward without Author identity unknown.

## No-spec Rationale

Post-merge archive of CHG-0018 plus CI workflow fix for git author identity required by git notes add during attest forward on GHA runners. No Rune library or canonical contract change.
