---
change: CHG-0065-record-that-the-wide-character-cell-model-was-built-and-measured-worse-than-the
artifact: context
---

# Context

The last of the five renderer gaps. A width table plus a cell model was built,
passed 8/8 on its own probe, and was reverted the same session because it made
real agent output worse.

Against a live grok session that had emitted a CJK table:

    one-column (shipped)   "東京  Tokyo"     "大阪  Osaka"
    cell model (reverted)  "東 京  Tokyo"    "東h京   Tokyo"

The width table was not the problem and was correct. The problem is that a row
is a String whose index is its column, so a wide glyph has to be stored as a
base plus a continuation cell — and every other grid operation manipulates that
String directly, knowing nothing about the pair. DCH, ICH, ECH and EL all split
one, and the orphan renders as a space. A TUI repaints constantly, so those are
the operations it uses most.

I nearly reported the opposite. The first comparison filtered rendered rows by a
CJK substring and showed rows for the new renderer and none for the old, which
read as an improvement. Widening the filter to any CJK codepoint showed four
clean rows for the old renderer and four corrupted ones for the new.
