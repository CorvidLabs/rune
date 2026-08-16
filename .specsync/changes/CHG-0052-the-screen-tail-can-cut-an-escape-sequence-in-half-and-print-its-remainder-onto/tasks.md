---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: tasks
---

# Tasks

- [x] `resync` past a sliced sequence, bounded at 256 bytes
- [x] regression tests at every cut offset, verified to fail without the fix
- [x] bound tested from both sides: no escapes at all, and an escape past the scan
- [x] docs state the window's cost and the never-erases caveat
