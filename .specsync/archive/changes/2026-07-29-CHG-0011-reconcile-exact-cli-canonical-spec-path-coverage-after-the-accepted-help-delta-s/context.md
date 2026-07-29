---
change: CHG-0011-reconcile-exact-cli-canonical-spec-path-coverage-after-the-accepted-help-delta-s
artifact: context
---

# Context

CHG-0010 accepted and applied the help contract to the CLI canonical spec, but its affected path
used the broad `specs` prefix. CHG-0008's accepted evidence tracks the exact
`specs/cli/cli.spec.md` delivery input. SpecSync 5.2.0 does not treat the broad prefix as exact
successor coverage, so strict validation correctly reports CHG-0008 as stale.

The contract itself is already correct and accepted. This operations-only record declares the
exact path, preserves the current canonical content, and provides an append-only audited successor
instead of weakening or bypassing the stale-evidence gate.
