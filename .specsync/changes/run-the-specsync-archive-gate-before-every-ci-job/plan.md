---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: plan
---

# Plan

## Approach

Add a first job, id `archive-gate` with display name `Archive`, to every
workflow that runs on pull requests or pushes (`ci.yml`, `trust.yml`). It checks
out the pull request head without persisting credentials and runs
`CorvidLabs/spec-sync@106aaa43d0bcf049f19b173ddb63815a25c3f931` with
`archive-gate-only: 'true'`. Every other job in those workflows gets
`needs: archive-gate`. Everything else in the files stays byte-for-byte.

## Out of scope

- `publish-package.yml`, which runs only on `release` and `workflow_dispatch`.
- The org ruleset that requires the `Archive` check (configured separately).
- Archiving or otherwise touching the preexisting open changes CHG-0073 to CHG-0080.
- Changing the existing Spec Sync job's pinned version (6.0.0) or its inputs.

## Steps

1. Insert the `archive-gate` job at the top of `jobs:` in `ci.yml`, reusing that
   file's `actions/checkout@v6`.
2. Add `needs: archive-gate` to the `verify` matrix, `spec-sync` and `intent` jobs.
3. Insert the same job in `trust.yml`, reusing its pinned
   `actions/checkout@9c091bb...` (v7.0.0), and add `needs: archive-gate` to `trust`.
4. Parse both files and print each job's `needs` to confirm the graph.

## Risks

- While any change is open on the branch or on `main`, CI runs only the Archive
  job, so feedback from the test matrix arrives only after archiving. That is the
  intended behaviour.
- The action is pinned to a `main` commit instead of a release; it must be moved
  to the first release with the gate.
- Adds roughly one short job (well under the 5 minute timeout) before the rest of
  CI.

## Constraints consulted

- AGENTS.md: the change lifecycle is not optional, so this change records the
  workflow edits; approval happens only after the definition is final.
- AGENTS.md: the CorvidLabs trust toolchain block — the trust gate is kept in
  place and not weakened (the `trust` job still runs, now after Archive);
  provenance stays off.
- AGENTS.md: README.md, CHANGELOG.md and shared specs are not touched, so no
  accepted change is staled by this one.
