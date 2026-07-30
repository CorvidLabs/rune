---
change: CHG-0011-reconcile-exact-cli-canonical-spec-path-coverage-after-the-accepted-help-delta-s
artifact: testing
---

# Testing

- Compare `specs/cli/cli.spec.md` before and after the reconciliation; only lifecycle metadata may
  change.
- Run `specsync change verify` and record exact evidence.
- Run `fledge spec check --strict`.
- Run `fledge trust verify`, including Augur and Attest through the configured trust workflow.
