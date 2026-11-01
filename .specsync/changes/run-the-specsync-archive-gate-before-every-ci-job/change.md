---
id: run-the-specsync-archive-gate-before-every-ci-job
state: implementing
type: operations
base_commit: 252702cf4d355076b9a4d2533e1d506aad3b0f02
---

# Run the SpecSync archive gate before every CI job

## Intent

Run the SpecSync archive gate before every CI job

## Affected Canonical Specs

- None

## Acceptance Criteria

- ci.yml and trust.yml each start with a job named Archive (id archive-gate) that checks out the pull request head and runs CorvidLabs/spec-sync pinned at 106aaa43d0bcf049f19b173ddb63815a25c3f931 with archive-gate-only: 'true'; every other job in those workflows (Ruby matrix, Spec Sync, Intent, trust) has needs: archive-gate, so a pull request with any open change under .specsync/changes/ runs nothing else until it is archived. publish-package.yml (release/workflow_dispatch only) is unchanged.

## No-spec Rationale

CI workflow ordering only; no canonical spec owns .github/workflows
