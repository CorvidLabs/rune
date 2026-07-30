---
change: CHG-0011-reconcile-exact-cli-canonical-spec-path-coverage-after-the-accepted-help-delta-s
artifact: requirements
---

# Requirements

## R1 — Exact successor coverage

The change MUST claim `specs/cli/cli.spec.md` exactly and follow both CHG-0008 and CHG-0010.

## R2 — No contract mutation

The accepted CHG-0010 CLI contract MUST remain unchanged. This change records delivery coverage
only and MUST NOT add, remove, or reinterpret public behavior.

## R3 — Strict lifecycle health

Strict SpecSync validation and the unified trust gate MUST complete with no stale accepted evidence.
