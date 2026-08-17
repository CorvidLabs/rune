---
change: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
artifact: docs
---

# Docs

No guide changes. The `usage` line already listed the subcommands and stays as
it is — this adds a machine-readable form beside it rather than replacing the
human one. `cli.spec.md` invariant 13 carries the contract, including the reason
the declared and dispatched lists are kept separate.
