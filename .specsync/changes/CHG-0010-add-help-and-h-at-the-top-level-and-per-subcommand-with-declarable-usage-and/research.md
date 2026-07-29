---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: research
---

# Research

## Existing behavior

Rune already separates its own flags from child arguments at the first `--`, and every command
returns a `Result` that a renderer formats for human or agent use. The help implementation follows
both conventions rather than creating a separate printing path.

## Review findings

Ruby's `Enumerable#any?` short-circuits after the first truthy deletion. It therefore cannot both
detect help and guarantee removal of all aliases. A full pre-separator filter is required.

`CLI#run` terminates with `SystemExit`, but tests and embedders can rescue it and reuse the object.
All mode state must consequently be initialized per call, not assumed to be single-use.

## Compatibility

The feature adds aliases and metadata without changing existing command parsing. It retains zero
external runtime dependencies and supports all existing output modes.
