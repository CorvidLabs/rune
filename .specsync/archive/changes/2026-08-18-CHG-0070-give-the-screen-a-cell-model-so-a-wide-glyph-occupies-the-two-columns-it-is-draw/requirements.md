---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: requirements
---

# Requirements

1. A column index is an array index, so a cell can hold a glyph plus its marks
   without moving the cells after it.
2. A wide glyph occupies two columns, wraps rather than splitting at the margin,
   and blanks both halves when either is destroyed.
3. A zero-width character occupies none and stays attached.
4. Every operation that slices a row leaves the pair invariant intact.
5. Plain ASCII rendering is unchanged.
