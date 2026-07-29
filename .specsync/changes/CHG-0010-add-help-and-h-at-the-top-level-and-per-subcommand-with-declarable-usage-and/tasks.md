---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: tasks
---

# Tasks

- [x] T1 Add `usage`, `flag`, `command_usage`, and `command_flags` to `Rune::Command`.
- [x] T2 Add structured overview and command help payloads and human rendering.
- [x] T3 Route top-level and per-command help without invoking command execution.
- [x] T4 Declare usage for every shipped command and flags for `run` and `watch`.
- [x] T5 Preserve help-looking arguments after the first `--`.
- [x] T6 Remove the unused `optparse` dependency.
- [x] T7 Update canonical specs, README, getting-started guide, and changelog.
- [x] T8 Remove every mixed or repeated pre-separator help alias.
- [x] T9 Reset renderer selection for every reused `CLI` invocation.
- [x] T10 Add regression tests for T8 and T9.
- [ ] T11 Run the full verification and trust gates.
