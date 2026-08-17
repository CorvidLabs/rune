---
change: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
artifact: context
---

# Context

A field report from driving `grok` and `kimi` through real work found that rune
answers structurally at one level and with a display string at the next.
`rune --help --json` returns `commands: [{name, summary}, …]`. `rune session
--help --json` returned no `commands` key at all — its seven subcommands
appeared only inside the `usage` line, as `<start|send|read|attach|list|stop|archive>`.

The reporter had to parse JSON for the first level and then split a human-facing
string on `|` for the second. Their words: "An agent parsing structurally must
fall back to string-splitting one level down." rune exists to be driven by
agents, so a surface that is discoverable for exactly one level is a defect in
the thing it is for.

Confirmed still present on this branch before the fix:

    rune --help --json          -> keys [commands, global_flags, version]
    rune session --help --json  -> keys [command, summary, usage, flags, …]   (no commands)
