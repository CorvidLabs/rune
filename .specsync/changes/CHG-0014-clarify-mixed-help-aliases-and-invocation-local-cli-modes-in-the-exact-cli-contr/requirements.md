---
change: CHG-0014-clarify-mixed-help-aliases-and-invocation-local-cli-modes-in-the-exact-cli-contr
artifact: requirements
---

# Requirements

## R1 — Mixed aliases

The CLI error-case table MUST state that every mixed or repeated help alias is consumed and help
returns exit status 0.

## R2 — Invocation isolation

The invocation-local invariant MUST explicitly prohibit prior help, JSON, or NDJSON flags from
affecting a later call on the same `CLI` instance.

## R3 — Exact semantic coverage

The `cli` semantic delta MUST be based on `e3b9064` and own `specs/cli/cli.spec.md` exactly.

## R4 — Verification

Strict SpecSync and the unified trust gate MUST pass without stale accepted evidence.
