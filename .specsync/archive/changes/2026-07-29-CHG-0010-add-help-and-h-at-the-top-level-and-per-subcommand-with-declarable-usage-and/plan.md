---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: plan
---

# Plan

1. Restack the help feature on PR #22's merge commit and create CHG-0010.
2. Add command usage and flag declarations plus structured help payloads.
3. Route top-level and per-command help before command execution.
4. Preserve the first-`--` boundary for child arguments.
5. Replace short-circuiting help extraction with a complete pre-separator filter.
6. Reset CLI rendering state at the start of each invocation.
7. Add regression tests for duplicate aliases and reused CLI instances.
8. Update canonical specs and user documentation.
9. Run the Fledge verification lane, smoke tests, strict SpecSync, Augur, Attest, and the unified
   trust gate.
