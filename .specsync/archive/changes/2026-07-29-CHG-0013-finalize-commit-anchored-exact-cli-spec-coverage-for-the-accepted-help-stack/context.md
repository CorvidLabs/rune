---
change: CHG-0013-finalize-commit-anchored-exact-cli-spec-coverage-for-the-accepted-help-stack
artifact: context
---

# Context

SpecSync successor coverage is commit-anchored. CHG-0008 through CHG-0012 were accepted while their
lifecycle updates were still uncommitted, so later records could not prove that their base
contained the earlier accepted delivery evidence. Commit `bf384e4` now contains the complete
accepted stack and final CLI contract.

This record anchors the exact `specs/cli/cli.spec.md` path to that commit without changing the
contract.
