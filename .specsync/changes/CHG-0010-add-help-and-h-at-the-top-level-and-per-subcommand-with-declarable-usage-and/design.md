---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: design
---

# Design

## Command declarations

`Rune::Command` gains `usage` and `flag` DSL methods alongside `name` and `summary`. Each subclass
owns its own flag array, and `command_flags` always returns an array so renderers need no nil guard.

## Help extraction

`Rune::Help.extract_flag!` splits argv at the first `--`. It scans the pre-separator portion once,
removes every recognized alias, and accumulates whether any alias was present. The post-separator
tail is preserved byte-for-byte. Detection and deletion are deliberately separate from
short-circuiting predicates.

## Routing and invocation-local rendering

`CLI#run` extracts output flags and help aliases before resolving the command. It dispatches either
to overview help, command help, or the command itself. Help remains a structured `Result`.

Help rendering state is reset at the start of every `run` invocation. This preserves the current
renderer interface while ensuring a reused `CLI` instance cannot leak help mode into a later
normal command. Output modes are likewise recalculated per invocation.

## Payloads

Overview help contains registered commands, global flags, and the Rune version. Command help adds
the command name, summary, declared usage, and declared flags. Human mode renders these payloads
with `Rune::Help`; JSON and NDJSON modes expose them directly.

## Rejected alternatives

- `OptionParser` was rejected because commands intentionally retain their existing parsing and
  separator semantics; constructing a parser only for display would create a second source of
  truth.
- A global flag registry was rejected because declarations should remain next to the command that
  owns and parses them.
- Automatic parsing introspection was rejected because existing command parsing uses inline
  patterns that do not provide a reliable public schema.
