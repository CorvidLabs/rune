---
change: CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim
artifact: context
---

# Context

Field feedback from an agent that spent a day driving grok through rune to do real work on another
repository — eight one-shot dispatches and a live session, with measurements rather than opinions.

Three of its findings are addressed here. Two were places where the documentation asserted something
that a day of real use disproved, which is worse than an absent doc: a caller had already built on
both claims.

Its most important finding — that polling `--screen` can return a half-painted frame, producing a
false "finished" — is deliberately *not* addressed here. An attempt to fix it measured no better
than the status quo, and shipping an unproven fix for a failure that is silent and points toward
"looks done" would be worse than leaving it documented. A reproducer has been requested.
