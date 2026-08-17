---
change: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
artifact: plan
---

# Plan

1. Move the four questions and the loader, keeping `dropped` on the object rather than as an
   argument.
2. Retarget the tests that reached into the command's privates.
3. Confirm the rotation and search regressions still pass, since those encode the cursor semantics
   callers depend on.
