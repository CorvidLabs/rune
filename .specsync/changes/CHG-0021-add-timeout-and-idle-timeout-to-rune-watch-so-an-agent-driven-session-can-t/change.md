---
id: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
state: accepted
type: feature
base_commit: 98894483a078c7e3fcf3739086d4b2cc88a00cd3
---

# Add --timeout and --idle-timeout to rune watch so an agent-driven session can't hang forever, closing #14

## Intent

Add --timeout and --idle-timeout to rune watch so an agent-driven session can't hang forever, closing #14

## Affected Canonical Specs

- `watch`

## Acceptance Criteria

- rune watch --timeout=SECONDS kills the session after N total seconds and rune watch --idle-timeout=SECONDS kills it after N seconds with no output and no input, in both cases via SIGKILL+reap (no orphaned child), reporting exit code 124 and truncated result fields (timed_out: true, timeout_kind); neither option changes default result data when unset; both options may be combined; malformed values are rejected before spawning anything; specs/watch/watch.spec.md documents the new flags, invariants, and error cases; new RSpec coverage for PTYWatcher and WatchCommand passes; fledge lanes run verify passes.

## No-spec Rationale

Not applicable
