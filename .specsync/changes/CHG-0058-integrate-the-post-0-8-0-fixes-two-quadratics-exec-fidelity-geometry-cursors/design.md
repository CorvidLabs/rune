---
change: CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors
artifact: design
---

# Design

The branch is a sequence of independently verified fixes rather than one design, and the notes below
are the record of what each one cost to find.

Two quadratics in the send path, not one. The named one was `--wait-for-regex` rescanning the whole
slice per tick; underneath it `byteslice` marked a String shared, so the next append copied the
entire transcript — 85% of supervisor time in one memmove, on the *default* path.

A one-element argv array was splatted into `PTY.spawn`, which Ruby routes through `/bin/sh`, so
`rune run -- "/opt/my program"` ran `/opt/my` and reported success. `ExecArgv` forces the
`[cmdname, argv0]` form for the array case only; a String command is still a command line.

`--screen` rendered at a hardcoded 40x120 while `attach` resized the child, and the window was
sized by a formula assuming eight bytes of escape per row — roughly 50x wrong for a real TUI.

Transcript cursors subtracted one global total, correct only while rotation was the sole source of
`truncated`; recording failed writes emits them mid-stream.
