---
change: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
artifact: plan
---

# Plan

The private-mode and ANSI-mode forms are dispatched before the guard that
drops every `?`-prefixed sequence, into `Screen#private_modes` / `#ansi_modes`.
`Screen` holds the alternate grid in one field, so "am I alternate" and "what do
I restore" cannot disagree.

Charset designation moves out of `IGNORED` — it was consumed there, which was
right while nothing could act on it — and SO/SI move out of the dropped-byte
case into a table, alongside the existing `CONTROLS` table and for the same
stated reason.

Double-width is deliberately *not* attempted here. It needs a cell model where
one glyph spans two columns plus an East Asian Width table, which is a different
size of change from the four above, and bundling it would put a speculative
rewrite in the same commit as four measured fixes.
