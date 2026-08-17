---
change: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
artifact: tasks
---

# Tasks

- [x] `subcommand` DSL and `command_subcommands` reader on `Command`
- [x] `Help#for_command` emits `commands` when non-empty; `render_command` prints them
- [x] Declare the seven session subcommands with summaries
- [x] Tests: payload shape matches the top-level shape; declared equals dispatched; absent for `run`
- [x] Verify each test fails against deliberately unfixed code
- [x] `cli.spec.md`: two export rows and invariant 13
