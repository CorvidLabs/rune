---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: requirements
---

# Requirements

## R1 — Top-level aliases

`rune --help`, `rune -h`, and `rune help` MUST return the command overview and exit 0.

## R2 — Command help

`rune <command> --help`, `rune <command> -h`, and `rune help <command>` MUST return that command's
summary, usage, and flags without executing the command or constructing a PTY runner.

## R3 — Structured output

Help MUST be represented as a normal `Result` and render correctly in human, JSON, NDJSON, and
piped modes.

## R4 — Declarable command surface

Command subclasses MUST declare usage and flags through the `Command` DSL. Flag storage MUST be
isolated per subclass and default to an empty array.

## R5 — Separator preservation

Help aliases MUST be interpreted only before the first `--`. Arguments at and after the separator
MUST be passed unchanged to the wrapped command.

## R6 — Unknown commands

Help for an unknown command MUST return a structured failure with exit status 1 rather than raise.

## R7 — Complete alias removal

Every recognized help alias before the separator MUST be removed while help intent is accumulated.
Mixed and repeated aliases, including `rune --help -h` and `rune --help --help`, MUST still resolve
to help.

## R8 — Invocation-local state

Reusing a single `CLI` instance for a help invocation followed by a normal invocation MUST NOT leak
help mode, output mode, or renderer selection between runs.

## R9 — Documentation

README and getting-started examples MUST use the `--` separator for wrapped commands, state the
separator rule, and document top-level, per-command, and structured help discovery.

## R10 — Dependency cleanup

The unused `optparse` require and its canonical-spec dependency entry MUST be removed.

## Out of scope

Command flag parsing remains unchanged. This feature adds declarations, discovery, rendering, and
correct invocation routing without replacing each command's parser.
