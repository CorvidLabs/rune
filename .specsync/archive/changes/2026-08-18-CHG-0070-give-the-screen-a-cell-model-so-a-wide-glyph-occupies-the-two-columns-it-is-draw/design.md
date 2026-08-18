---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: design
---

# Design

A row is an `Array`; a cell is `nil`, a `String` of one graphic plus its marks, or
`CONTINUATION`.

The alternative considered and rejected was keeping `String` rows and encoding a
wide glyph as base-plus-sentinel. That is what the first attempt did, and it
cannot hold: every operation slices the row directly, so any of them can strip a
sentinel or orphan one, and the orphan renders as a space. Twelve operations each
needing to know about pairs is twelve chances to forget.

The array makes two things true that the string could not. A cell holds any
number of characters without moving the cells after it, which is what makes
combining marks work at all. And the pair invariant can be restored *after* the
fact, in one `heal` pass, because a row is a sequence of cells rather than a
sequence of bytes — so `heal` is the only place that knows the rule, and a new
operation inherits it by construction rather than by remembering.

`pad`/`padded_line` disappear: assigning past the end of an array fills with nil
and a nil cell renders blank. That padding was the mechanism by which a column
index became an index into text.
