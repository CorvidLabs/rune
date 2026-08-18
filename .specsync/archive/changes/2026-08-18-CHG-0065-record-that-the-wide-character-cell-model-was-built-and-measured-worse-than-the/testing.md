---
change: CHG-0065-record-that-the-wide-character-cell-model-was-built-and-measured-worse-than-the
artifact: testing
---

# Testing

563 examples, 0 failures; rubocop clean; `harnesses/renderer_gaps.rb` shows four
of five gaps closed and double-width open, which is the state this records.

The evidence for the revert is the live-output comparison above, produced by
asking grok for a CJK table and rendering the captured transcript through both
implementations. The synthetic probes reproduce the mechanism:

    erase one cell inside a pair   "東 AB" -> "東 京AB"   under the cell model
    repaint over the left half     "h京AB" -> "h 京AB"    under the cell model

A third probe gives `京AB` under both and is recorded as baseline rather than
evidence, because listing it would have overstated the case.
