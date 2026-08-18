---
change: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
artifact: requirements
---

# Requirements

1. A flag-shaped token watch does not own is refused, not executed.
2. run and watch share one guard, because they had already drifted once.
3. `--grep` searches the slice `--since` selected.
4. `--max-output`/`--tail` bound every field they return; with neither set, the
   shape is byte-for-byte unchanged.
5. Each fix has a test that fails without it.
