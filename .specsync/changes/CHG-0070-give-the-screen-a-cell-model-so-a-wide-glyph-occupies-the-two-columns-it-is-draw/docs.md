---
change: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
artifact: docs
---

# Docs

`parsers.spec.md` invariant 17 is rewritten. It previously recorded that a cell
model had been measured worse and reverted; it now records the measurement that
reverses that, and says plainly that the earlier error was a mislabelled
comparison rather than a bad measurement. Leaving the old text in place would
have told the next reader not to attempt the fix that works.

`character_width.rb` joins the parsers module. Its table is a curated UAX #11
subset, deliberately not generated: rune carries no runtime dependencies, and
what it misses renders one column wide, which is what everything did before.
