---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: tasks
---

# Tasks

- [x] `Session::PendingSend`
- [x] supervisor delegates `begin_pending` and `resolve_pending`
- [x] moved constants follow the logic that uses them
- [x] echo tests retargeted at `PendingSend`
- [x] full suite green, lint clean
