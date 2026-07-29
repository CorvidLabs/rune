---
id: CHG-0011-reconcile-exact-cli-canonical-spec-path-coverage-after-the-accepted-help-delta-s
state: accepted
type: operations
base_commit: ef897af980c1b85b0a6b343e9e70b3bdb8ff1ed7
---

# Reconcile exact CLI canonical-spec path coverage after the accepted help delta so CHG-0008 has an audited successor

## Intent

Reconcile exact CLI canonical-spec path coverage after the accepted help delta so CHG-0008 has an audited successor

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- 1. The exact specs/cli/cli.spec.md delivery path is covered by an accepted successor to CHG-0008 and CHG-0010. 2. The canonical CLI contract remains unchanged from the accepted CHG-0010 result. 3. Strict SpecSync and the full trust gate pass with no stale accepted evidence.

## No-spec Rationale

CHG-0010 already applied the CLI semantic delta; this ledger-only successor records the exact canonical path required to cover CHG-0008's accepted delivery evidence without changing the contract again.
