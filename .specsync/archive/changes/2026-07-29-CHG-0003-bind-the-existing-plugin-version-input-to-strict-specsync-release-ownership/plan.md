---
change: CHG-0003-bind-the-existing-plugin-version-input-to-strict-specsync-release-ownership
artifact: plan
---

# Plan

1. Declare `plugin.toml` as the exact affected delivery path.
2. Preserve the strict `meaningful_paths` policy introduced by CHG-0002.
3. Verify version parity, tests, smoke behavior, strict SpecSync coverage, and trust.
4. Record provenance for the resulting audit-only commit.
