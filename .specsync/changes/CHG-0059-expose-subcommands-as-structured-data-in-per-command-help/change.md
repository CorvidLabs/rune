---
id: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
state: accepted
type: feature
base_commit: 7041cb9163a91f82075fe50e1be202ceba717a09
---

# Expose subcommands as structured data in per-command help

## Intent

Expose subcommands as structured data in per-command help

## Affected Canonical Specs

- `cli`
- `session`

## Acceptance Criteria

- rune session --help --json carries a commands array of {name, summary} entries, in the same shape rune --help uses for top-level commands, and its names equal SessionCommand::SUBCOMMANDS. A command with no subcommands emits no commands key, so run/watch/version help payloads keep their existing shape. The human rendering gains a Subcommands block. Tests cover all three, and each was verified to fail against deliberately unfixed code.

## No-spec Rationale

Not applicable
