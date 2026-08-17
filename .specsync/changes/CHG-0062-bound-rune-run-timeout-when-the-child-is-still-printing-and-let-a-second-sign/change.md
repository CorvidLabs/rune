---
id: CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign
state: accepted
type: feature
base_commit: 05aa9661a7dbc4444ca61cbff7936c0a40b4ce4b
---

# Bound rune run --timeout when the child is still printing, and let a second signal stop rune

## Intent

Bound rune run --timeout when the child is still printing, and let a second signal stop rune

## Affected Canonical Specs

- `pty_runner`
- `watch`

## Acceptance Criteria

- rune run --timeout returns at its deadline even when the child is actively printing at the moment of the kill: four ladder cases all return 124 within ~5.5s, where two hung past 40s on v0.8.0. Every trapped INT/TERM reaches the child rather than being overwritten within one poll. A second signal within a 5s burst window is forwarded to the child first and then unwinds rune to a well-formed result at 128+signo, with traps restored to DEFAULT so a third signal is the last escape hatch. rune watch is unaffected because raw mode clears ISIG. The full suite, lint and release lane pass on the merged tree.

## No-spec Rationale

Not applicable
