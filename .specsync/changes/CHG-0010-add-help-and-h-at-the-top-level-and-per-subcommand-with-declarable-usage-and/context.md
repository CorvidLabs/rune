---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: context
---

# Context

An independent audit found that Rune did not recognize `--help` or `-h`. Top-level help aliases
failed as unknown commands, while `rune run --help` attempted to execute `--help` inside a PTY and
returned the child failure. The existing `rune help` command also could not expose the command
flags declared only in specs and error messages.

The help feature was originally prepared before PR #22 merged. PR #22 changed the trust workflow
and occupied the previous SpecSync sequence, so this change restacks the feature on merge commit
`0b2218b4b054368a0cd6562e289ffff9f9199395` and records it as CHG-0010.

Review of the original implementation found two additional correctness defects:

1. `Help.extract_flag!` used a mutating `any?` expression. Ruby short-circuits `any?`, so once one
   alias was deleted, later mixed or repeated aliases remained in argv and could be treated as a
   command.
2. `CLI` stored help rendering state in `@help_mode` without resetting it. Reusing one CLI instance
   for a help call and then a normal call could route a normal result through the help renderer.

The documentation also taught separator-free wrapped commands, allowing Rune flags to consume a
child command's identically named flags. This change documents and tests the separator-safe form.
