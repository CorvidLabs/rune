---
change: CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0
artifact: testing
---

# Testing

Sixteen new renderer examples drawn from grok's comparison table, covering the escapes that move the
cursor, the four last-column cases, and the insert/delete/scroll family. Every expectation is what a
real terminal produces, not what the previous implementation produced.

The teardown fixes were verified end to end against a live session stopped mid-send, before and
after, and the renderer rewrite re-checked against captured real transcripts.

360 examples, 0 failures; lint clean.
