---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: context
---

# Context

This is the CorvidLabs org-wide rollout of the SpecSync archive gate added in
CorvidLabs/spec-sync#832 (merged as `106aaa43d0bcf049f19b173ddb63815a25c3f931`),
approved by 0xLeif. The goal is that every SpecSync change is archived before a
pull request merges, and that CI runs nothing else until it is. The same recipe
was first applied to CorvidLabs/chough (PR #18).

What a session picking this up needs to know:

- The action input `archive-gate-only: 'true'` runs only
  `.github/scripts/archive-readiness.sh` (bash + python3, no binary download) and
  fails while any change under `.specsync/changes/` is still open.
- Published releases up to and including v6.1.1 ignore that input, so the step
  pins the commit `106aaa43d0bcf049f19b173ddb63815a25c3f931` rather than a tag.
  Move to the first release that carries the gate once it is published.
- A skipped job counts as passing for branch protection, so merge blocking relies
  on an org ruleset that requires a check named `Archive`. That ruleset is
  configured separately and is not part of this change.
- At the time of writing, changes CHG-0073 to CHG-0080 are still open on `main`.
  Until their owners archive them, the new Archive check on this branch is
  expected to be red. This change does not touch them.
