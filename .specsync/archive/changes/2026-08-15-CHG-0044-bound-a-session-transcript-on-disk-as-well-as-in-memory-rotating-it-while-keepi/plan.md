---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: plan
---

# Plan

1. Confirm nothing prunes: `store.remove` unused, `archive` moves rather than prunes.
2. Rotate in the store, since it owns the file; trigger from the supervisor, which knows the size.
3. Make the reader account for dropped bytes so cursors keep their meaning.
4. Verify the accounting is exact rather than approximately right.
