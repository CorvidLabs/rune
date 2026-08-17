---
change: CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim
artifact: testing
---

# Testing

Four tests: matching lines are kept and counted, `--context` includes neighbours, a pattern spanning
an escape sequence still matches because the search runs on cleaned text, and an unparseable pattern
returns `grep_error` with a successful result.

The third is the one that matters — it is the case that would have made the feature look broken in
exactly the situation it exists for.

386 examples, 0 failures; lint clean.
