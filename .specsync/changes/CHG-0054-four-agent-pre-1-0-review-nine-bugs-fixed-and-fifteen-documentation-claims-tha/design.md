---
change: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
artifact: design
---

# Design

**The echo bug** was a nil clock. `observe` passed `now: nil`, and `beyond_echo`'s partial-echo
guard reads `if now && ...`, so the guard was unreachable from the one caller that needed it.
Threading the loop's clock through is the whole fix; `observe` also returns early once the flag has
latched, which removes the quadratic rescan.

**The crash** was counts used unclamped as loop and allocation bounds. `span` clamps to the
dimension each sequence operates on, which is what a real terminal does.

**Printed sequences** had three causes and one symptom. The CSI pattern is now the ECMA-48 grammar
(parameters, then intermediates, then a final byte); the ignore list is a table rather than a chain,
because anything missing from it is printed; and a sequence the stream ended inside is consumed.

**Scroll regions** touch every vertical motion, so `newline`, `reverse_index`, IL, DL, SU and SD
all route through two region-aware helpers. With the default region those are the whole screen, so
the ordinary path is unchanged — which the existing tests confirm.

**Erase** stops using `else` as 'erase everything'. Only defined parameters act.
