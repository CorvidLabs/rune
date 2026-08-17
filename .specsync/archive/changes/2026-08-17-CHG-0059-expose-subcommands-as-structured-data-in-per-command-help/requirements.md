---
change: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
artifact: requirements
---

# Requirements

1. `rune <command> --help --json` carries a `commands` array for a command that
   dispatches subcommands, with `{name, summary}` entries — the same key and
   entry shape `rune --help` already uses, so one parser reads both levels.
2. A command with no subcommands emits no `commands` key. Existing payloads for
   `run`, `watch`, and `version` keep their exact shape; this is additive only.
3. The declared list may not silently diverge from the dispatched list.
4. The human rendering shows the subcommands too, since `--help` without `--json`
   is what a person runs.
