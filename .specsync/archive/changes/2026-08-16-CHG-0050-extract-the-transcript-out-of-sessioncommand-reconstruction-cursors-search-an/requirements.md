---
change: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
artifact: requirements
---

# Requirements

1. Reading, cursors, search and rendering must be exercisable without constructing a command.
2. Behaviour must not change: the regression tests for rotation accounting and search must pass
   untouched in substance.
3. Cursor semantics must stay identical across rotation, since callers hold those values.
