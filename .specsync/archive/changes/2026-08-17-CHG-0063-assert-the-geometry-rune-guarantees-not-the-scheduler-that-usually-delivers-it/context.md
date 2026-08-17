---
change: CHG-0063-assert-the-geometry-rune-guarantees-not-the-scheduler-that-usually-delivers-it
artifact: context
---

# Context

CI on Ruby 3.1 failed with

    expected "SIZE:[0, 0]\rRESIZED:[40, 120]\r" to include "SIZE:[40, 120]"

The child read its winsize before the supervisor had set it, then received the
SIGWINCH and reported the right size. Every other Ruby version won that race, so
the spec had passed since it was written.

`PTY.spawn` returns the master only once the child is already running, so
`apply_window_size` is necessarily a spawn-then-set. A child that reads its
winsize immediately can therefore see 0x0. That is a property of the spawn path,
not a flake, and the spec was asserting the scheduler rather than the guarantee.
