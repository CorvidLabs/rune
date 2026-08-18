---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: research
---

# Research

Three questions had to be settled before touching the grid.

**Was the earlier "measured worse" conclusion right?** No. Rendering the same
56,928-byte grok capture through three explicit revisions shows the one-column
model corrupting real output at `cc8bb3c` and `ad76e22` alike, and only the cell
model producing `東京`. The earlier A/B compared two working trees and got the
sides the wrong way round.

**Could one of the four renderer fixes since have caused it instead?** No. Each
was disabled in turn on top of `main` — the alternate screen buffer, DECAWM, IRM,
and the charset designation — and the corrupted rows are byte-identical in all
four cases. It is the column arithmetic, not the modes.

**What does a terminal actually do when half a wide glyph is destroyed?** It
blanks both halves; half a character is not something it can show. That is the
rule `heal` implements, and it is why the probes now return `  京AB` rather than
an orphan.

Width data comes from UAX #11 East_Asian_Width (W and F) plus Emoji_Presentation,
and the combining-mark ranges for zero width. Not generated from the full
database: rune carries no runtime dependencies, and an uncovered codepoint
renders one column wide, which is what every codepoint did before.
