---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: design
---

# Design

`tail` resyncs to the first `ESC` in the window. The remainder of a sliced sequence has no
`ESC` left to identify it, so the renderer prints it — cutting inside `\e[?2026h` puts a
literal `?2026h` on screen at whatever position the cursor holds.

The scan is bounded at 256 bytes because a cut can equally land in plain text, where the two cases
are indistinguishable. Dropping a couple of lines from the start of a 256KB window costs nothing —
that first line is already documented as unreliable — while resyncing to a distant escape in a
mostly-text stream would discard the whole screen.

The old comment asserted the opposite: that a partial sequence 'is consumed harmlessly as text'.
It is consumed as text, and that is exactly the harm.
