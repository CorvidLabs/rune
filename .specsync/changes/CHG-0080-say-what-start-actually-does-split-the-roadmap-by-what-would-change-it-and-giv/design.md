---
change: CHG-0080-say-what-start-actually-does-split-the-roadmap-by-what-would-change-it-and-giv
artifact: design
---

# Design

## Codes as data, not as a new envelope

`Result.failure` already took `data:` and `to_h` already emitted it, so no envelope shape changes:
a failure that previously read `{status, error}` now reads `{status, data: {code, name}, error}`.
Adding a key is additive for every reasonable consumer; changing prose is not. That asymmetry is
the whole argument for doing it before the freeze.

A private `failure(code, message, name:)` helper wraps `Result.failure` so a call site cannot add a
message without a code by accident, and so the shape is declared in one place.

## Not annotating all 37 sites

The codes cover the conditions a caller branches on: session not found, not running, already
running, being started, launch failed, unknown subcommand. Usage errors and validation failures are
left with prose for now, deliberately — they are read by humans fixing a command line, not by
retry loops. Documenting that the set grows is what keeps that decision from becoming a wart:
a consumer that treats an unknown code as generic is unaffected by later additions.

## Splitting the roadmap by consequence rather than by topic

The section was organised by what each item *is*. It is now organised by what would change it —
gates versus documented limitations — because that is the question a reader of a pre-1.0 roadmap
is actually asking. Moved items keep their full text; the record of what was tried is what stops
it being tried again, so nothing was deleted to make the list shorter.
