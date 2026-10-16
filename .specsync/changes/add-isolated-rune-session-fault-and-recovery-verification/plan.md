---
change: add-isolated-rune-session-fault-and-recovery-verification
artifact: plan
---

# Plan

## Approach

Exercise the existing PTY session API with private fixture homes and recorded
positive PID/start-time identities. Probe failure, reconnect, isolation and
bounded-output behavior. Test assertion sensitivity against disposable product
copies and injected cleanup failures.

## Out of scope

No Rune implementation changes, default-home session access, process-group
signals, wire/API changes, dependency downloads, policy changes or publication
from the worker. Human approval and lifecycle finalization remain pending.

## Steps

1. Inventory existing session contracts and tests.
2. Add the isolated harness and 17 focused examples.
3. Review signal identity and cleanup semantics before live fixture execution.
4. Run actual product mutants and the old-cleanup negative control.
5. Run focused/full native checks and review exact candidate hashes.
6. Publish a coordinator-reviewed draft only after committed-range checks.

## Risks

An unsafe harness could signal an unrelated process or hide an unresolved
fixture. Every real signal requires a tracked positive PID and equal nonempty
start-time identities. Unresolved cleanup preserves evidence and fails. A
mutation setup failure is not counted as a rejected product regression.

## Constraints consulted

AGENTS.md requires measured claims and tests that fail against broken code.
Fixture subprocesses inherit private homes. No protection or lifecycle gate is
weakened, and no human intent or acceptance is synthesized.
