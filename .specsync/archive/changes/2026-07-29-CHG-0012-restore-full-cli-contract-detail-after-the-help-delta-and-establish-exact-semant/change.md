---
id: CHG-0012-restore-full-cli-contract-detail-after-the-help-delta-and-establish-exact-semant
state: archived
type: documentation
base_commit: ef897af980c1b85b0a6b343e9e70b3bdb8ff1ed7
---

# Restore full CLI contract detail after the help delta and establish exact semantic successor coverage

## Intent

Restore full CLI contract detail after the help delta and establish exact semantic successor coverage

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- 1. The CLI invariants retain the complete stdout-purity, help routing, duplicate-alias, and invocation-local-state rationale. 2. Behavioral examples retain concrete parseability and separator cases. 3. The exact specs/cli/cli.spec.md semantic delta succeeds CHG-0008 and CHG-0010. 4. Strict SpecSync and the full trust gate pass without stale evidence.

## No-spec Rationale

Not applicable
