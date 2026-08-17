---
change: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
artifact: plan
---

# Plan

Add a `subcommand(name, description)` DSL to `Command`, mirroring the existing
`flag` DSL, accumulating into `command_subcommands`.

`Help#for_command` builds its payload as before and appends `commands` only when
the class declared any — the guard is what keeps every other command unchanged.

`SessionCommand` declares its seven, immediately above the `SUBCOMMANDS` constant
that dispatches them, so the two are edited in the same place.

Deliberately not done: deriving the list from `SUBCOMMANDS` automatically. That
would remove the drift risk but leaves nowhere to put a summary, and a bare name
list is barely better than splitting the usage string. Declaring both and
asserting they match keeps the summaries and makes drift a test failure.
