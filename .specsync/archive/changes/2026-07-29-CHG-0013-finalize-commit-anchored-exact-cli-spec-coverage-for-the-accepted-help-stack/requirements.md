---
change: CHG-0013-finalize-commit-anchored-exact-cli-spec-coverage-for-the-accepted-help-stack
artifact: requirements
---

# Requirements

## R1 — Committed base

The base commit MUST contain all accepted predecessor lifecycle evidence and the final CLI spec.

## R2 — Exact coverage

The change MUST claim `specs/cli/cli.spec.md` exactly and follow the accepted predecessor stack.

## R3 — No contract mutation

The canonical CLI contract MUST remain unchanged.

## R4 — Green trust state

Strict SpecSync and the unified trust gate MUST pass without stale accepted evidence.
