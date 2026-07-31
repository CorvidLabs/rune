---
id: CHG-0019-set-git-author-identity-before-ci-attest-forward-on-gha-runners
state: accepted
type: bug_fix
base_commit: c6aa0fee4ce742207ab5de2dd4fa7e82971051d6
---

# Set git author identity before CI attest forward on GHA runners

## Intent

Set git author identity before CI attest forward on GHA runners

## Affected Canonical Specs

- None

## Acceptance Criteria

- Main push Trust gate runs attest forward without Author identity unknown; git user.name and user.email are set on the runner before git notes add.

## No-spec Rationale

CI workflow only: configure git user.name/user.email so attest forward can write notes commits on GitHub-hosted runners. No Rune library or canonical contract change.
