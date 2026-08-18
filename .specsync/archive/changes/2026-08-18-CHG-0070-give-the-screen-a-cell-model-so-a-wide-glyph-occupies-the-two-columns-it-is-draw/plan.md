---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: plan
---

# Plan

Rows become `Array`s of cells. A cell is `nil` (never written), a `String` holding
one graphic plus any combining marks, or `CONTINUATION`.

The operations convert almost one-for-one from string slicing to array slicing,
and `pad`/`padded_line` disappear: assigning past the end of an array fills with
nil and a nil cell renders blank, where a string row had to be padded by hand —
and that padding is what made every column index an index into text.

The one design decision worth naming: insert, delete, erase and scroll can each
separate a glyph from its continuation, and the first attempt tried to make each
of them pair-aware. It lost. This restores the invariant with a single `heal`
pass after each mutation — the same rule expressed once instead of twelve times,
and the thing a new operation cannot forget to do.
