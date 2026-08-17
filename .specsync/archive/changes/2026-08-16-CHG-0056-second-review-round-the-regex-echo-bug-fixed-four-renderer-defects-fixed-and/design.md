---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: design
---

# Design

**Echo location** moves from exact substring to **condensed** text — escapes and whitespace removed
from both sides, which is exactly the difference between what was sent and every transformed echo
that could be captured. The offset is memoised once found, the search is bounded, and a match that a
repainted copy of the input covers is vetoed.

**RIS and DECSTR** get real handlers. RIS was in the ignore list under a comment asserting ignored
escapes cannot move the cursor, which is false for a full reset. DECSTR carries an intermediate
byte, so both `csi_control` guards rejected it and its final byte is not in `CONTROLS` — it was
dropped twice over. The trigger for both is someone typing `reset` to recover a garbled TUI, which
is precisely when a region is live.

**Private markers**: `?` was guarded and `<`, `>`, `=` were not, though all four are ECMA-48
private-prefix bytes.

**Control bytes** are excluded from `PRINTABLE` and fall through to a case with no branch, so they
are consumed and dropped.
