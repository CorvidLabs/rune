---
change: CHG-0077-hold-an-escape-split-across-chunks-so-a-retained-renderer-matches-a-one-shot-ren
artifact: docs
---

# Docs

`specs/parsers/parsers.spec.md` gains `MAX_CARRY_BYTES` in the Public API table and two invariants:
that an instance renders the same screen however the stream is chunked, and that an ST terminator
split across chunks still reads as incomplete. The measured 10.4x figure and its explicit limit
(still above `POLL_INTERVAL`; `heal` is per-glyph) are recorded with the first of those, so the next
reader does not mistake this for having closed the cost question.

No user-facing documentation changes: `--screen` output is unchanged for every input a caller can
produce today, because nothing yet feeds a retained instance chunk by chunk. The one visible
difference is a bug fix — a transcript ending mid-ST no longer renders `]0;title` as visible text.
