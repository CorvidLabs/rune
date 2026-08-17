---
change: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
artifact: context
---

# Context

ROADMAP listed five renderer gaps as the only entry left on its re-measured
table. Each was measured against ECMA-48/xterm behaviour before anything was
written, in `harnesses/renderer_gaps.rb`:

    alternate screen buffer (1049)     GAP   PRIMARY_TEXT still on the grid
    restoring the primary buffer       GAP   nothing to restore
    autowrap off (DECRST 7)            GAP   wrapped where a terminal would not
    double-width characters            ok    <- wrong, see below
    DEC line drawing (ESC ( 0)         GAP   printed qqq
    insert mode (IRM)                  GAP   overwrote instead of inserting

The double-width probe was a test that could not fail. `日本語ABC` is what both
the correct and the naive renderer produce, because a string of one-column cells
and a string of two-column cells are the same string when nothing is positioned
after them. Rewritten against an absolute column, it fails: `\e[H日本語\e[1;7HX`
renders `日本語   X` where a terminal renders `日本語X`.

A fifth defect was found while dogfooding rather than from the list. Driving
Claude Code through `rune session`, every `clean_output` opened with a literal
`\e7\e8` — present uncapped as well as capped, so the stripper rather than the
truncation. `ScreenRenderer` already acted on `[DEM78c]`, so the two parsers in
this module disagreed about what an escape is.
