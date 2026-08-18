---
change: CHG-0072-snap-a-since-that-lands-inside-a-character-forward-instead-of-inventing-u-fff
artifact: docs
---

# Docs

`session.spec.md` invariant 51b carries the contract and the measurement. The `from` export
row now says a mid-character cursor snaps forward.

`docs/sessions.md` is left alone: it is translated into nine languages, and a one-sentence
English-only edit would stale them for a flag whose usual input (a cursor rune handed back)
never hits this path.
