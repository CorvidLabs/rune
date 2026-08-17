---
change: CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign
artifact: context
---

# Context

Two defects, found together because fixing the second exposed the first.

**The one that matters.** `rune run --timeout` never returned when the child was
still printing. The flag whose entire purpose is to bound a run did not bound it.
Present in every release through 0.8.0 and missed by every review round.

Reproduced against the released 0.8.0 with a hard 40s ceiling, rune s own output
redirected to a file so "rune has not exited" could not be confused with a
blocked reader — the rune process itself sat in state `S`:

    rune run --timeout=3 -- sh -c <case>          v0.8.0        merged
    ignores TERM, prints constantly               HUNG 40s+     124 in 5.5s
    ignores TERM, silent                          124 in 3.1s   124 in 3.2s
    handles TERM, prints constantly               HUNG 40s+     124 in 5.5s
    handles TERM, one burst then idle             124 in 3.2s   124 in 3.2s

Rows two and four are the diagnosis. Ignoring TERM was never the trigger, and a
child that has *stopped* printing exits cleanly. The discriminator is whether the
child is producing output at the moment of the kill: on macOS a pty child
SIGKILLed with bytes it wrote still unread wedges in the kernel exit path
(`ps` shows `?Es`), and only reading the master clears it.

That is exactly why nine releases of tests missed it — every fixture used a
silent child, which is a fixture more specific than the mechanism.

**The second.** Signal forwarding used a latch, so two signals arriving inside
one 0.2s poll overwrote each other, and no number of interrupts could stop rune
itself once a child ignored them.
