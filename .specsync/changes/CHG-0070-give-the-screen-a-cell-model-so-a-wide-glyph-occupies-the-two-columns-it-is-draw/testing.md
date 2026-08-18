---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: testing
---

# Testing

591 examples, 0 failures; rubocop clean; all five gaps ok in
`harnesses/renderer_gaps.rb`.

Controls:

    mutation                           failures
    width table forced to one column   4 of 136 parser examples
    `heal` made a no-op                2 of 136

Synthetic, against what a terminal gives:

    \e[H東京\e[1;5HX     -> "東京X"    (one column gave "東京  X")
    \e[H日本語\e[1;7HX   -> "日本語X"
    \e[HABC\e[1;3HX     -> "ABX"     (unchanged)

The pair-breaking probes that killed the first attempt now heal rather than leave
orphans: erasing inside a pair gives `  京AB`, deleting before one gives ` 京AB`,
and repainting over the left half gives `h 京AB` — both halves blanked in each
case, which is what a terminal does with half a character.
