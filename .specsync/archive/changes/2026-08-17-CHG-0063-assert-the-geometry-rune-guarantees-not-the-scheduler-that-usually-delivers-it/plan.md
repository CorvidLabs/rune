---
change: CHG-0063-assert-the-geometry-rune-guarantees-not-the-scheduler-that-usually-delivers-it
artifact: plan
---

# Plan

Both specs wait for the default geometry to appear at all, then accept it from
either `SIZE:` or `RESIZED:`. The first spec had no WINCH handler in its child,
so it gains one — without it, a child that lost the race could never report the
correction and the spec would hang rather than pass.

`session.spec.md` gains invariant 49a: the race, what closing it would cost
(opening the pty, sizing it, and spawning onto the slave by hand instead of
using `PTY.spawn`), and the case that genuinely loses — a child that reads its
size once at startup and never handles WINCH.

Deliberately not fixed here. Rewriting the spawn path is a real change with real
risk, and it would go in on the strength of a single CI observation with no
measurement behind it. This repository has shipped two documented limitations
for exactly that reason.
