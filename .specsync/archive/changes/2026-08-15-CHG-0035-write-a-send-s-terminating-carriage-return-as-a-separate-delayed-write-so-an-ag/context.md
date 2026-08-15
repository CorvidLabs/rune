---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: context
---

# Context

A loose thread from the previous round: in a concurrency test, claude's rendered screen did not
contain its answer while grok's and agy's did. It was written off as probable settle timing. It was
not.

Chasing it found that the prompt had been *typed into claude's composer and never submitted*. The
warmup `hi` went through; the real prompt sat there. rune reported `settled: true` throughout,
because the composer repaint is output and the settle window elapsed normally.

Bisecting by input length put the boundary between 61 and 82 characters, and every length above it
failed. An agent prompt is almost always longer than 64 characters, so for the single use case this
whole feature exists to serve — one agent CLI driving another — sends were silently not being
delivered.
