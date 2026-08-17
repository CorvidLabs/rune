---
change: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
artifact: docs
---

# Docs

`parsers.spec.md` gains invariants for each mode, the charset set, the sanitizer
gap, and the double-width limitation stated with the measurement that shows it.
`harnesses/renderer_gaps.rb` is the reproduction, and re-runnable.

ROADMAP still lists five renderer gaps and now overstates the problem; that entry
is left to the release commit that reports the round, rather than edited here
where it would stale every accepted change that lists the file.
