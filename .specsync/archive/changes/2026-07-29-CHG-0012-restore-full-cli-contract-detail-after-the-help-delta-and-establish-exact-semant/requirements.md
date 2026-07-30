---
change: CHG-0012-restore-full-cli-contract-detail-after-the-help-delta-and-establish-exact-semant
artifact: requirements
---

# Requirements

## R1 — Preserve prior rationale

The CLI spec MUST retain the complete end-to-end stdout-purity rationale from CHG-0008.

## R2 — Preserve help detail

The CLI spec MUST describe command non-execution, separator passthrough, structured discovery,
mixed/repeated alias removal, and invocation-local rendering state with concrete examples.

## R3 — Exact semantic successor

The change MUST own `specs/cli/cli.spec.md` exactly and apply a `cli` semantic delta after CHG-0008
and CHG-0010.

## R4 — Lifecycle health

Strict SpecSync and the unified trust gate MUST pass with no stale accepted evidence.
