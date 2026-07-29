---
change: CHG-0005-restrict-release-version-matching-to-the-plugin-toml-table
artifact: context
---

# Context

The release checker currently finds the first `version` key anywhere in `plugin.toml`, while the setter can cross from `[plugin]` into a later table. A malformed plugin table can therefore be accepted or cause an unrelated table to be rewritten. The latest outstanding PR review identified this against commit `24c591c`.
