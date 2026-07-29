---
change: CHG-0012-restore-full-cli-contract-detail-after-the-help-delta-and-establish-exact-semant
artifact: testing
---

# Testing

- Confirm all fifteen CLI invariants remain present.
- Confirm examples include whole-stdout JSON parsing, per-command help, separator passthrough,
  duplicate aliases, and CLI reuse.
- Run the configured SpecSync verification lane.
- Run `fledge spec check --strict` and `fledge trust verify`.
