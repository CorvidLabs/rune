---
change: CHG-0015-record-exact-supersession-for-the-committed-cli-help-contract-and-document-cli-r
artifact: requirements
---

# Requirements

## R1 — Committed base

The base commit MUST contain the accepted predecessor evidence and final CLI contract.

## R2 — CLI reuse contract

The error-case table MUST state that a reused CLI after help resets modes and dispatches normally.

## R3 — Fresh predecessor evidence

Every overlapping accepted record that becomes stale MUST be reopened, freshly verified, and
reaccepted against the final contract.

## R4 — Strict lifecycle health

Strict SpecSync and the unified trust gate MUST pass with no stale accepted evidence.
