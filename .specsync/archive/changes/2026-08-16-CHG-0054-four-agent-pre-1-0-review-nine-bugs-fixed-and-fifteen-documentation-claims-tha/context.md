---
change: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
artifact: context
---

# Context

Four independent agents reviewed rune before a pre-1.0 release, each on a different lens: renderer
correctness against two reference emulators, supervisor races and lifecycle, every factual claim in
the docs executed rather than read, and a session spent driving real multi-step work through it.

They found nine real bugs and fifteen wrong documentation claims. Two of the bugs are severe: one
made `send` return the caller's own words as the answer, and one let a single escape sequence in
child output crash the renderer.

The method is the point. Most of the sharpest bugs in this project have been found by an agent other
than the one that wrote the code, and this round is the strongest evidence yet.
