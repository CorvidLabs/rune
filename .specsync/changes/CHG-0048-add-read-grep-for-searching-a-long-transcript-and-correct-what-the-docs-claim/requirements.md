---
change: CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim
artifact: requirements
---

# Requirements

1. Finding one line in a long transcript must not require pulling the transcript.
2. A search must match what is on screen, not the repaint bytes.
3. A caller's bad regex must not fail the read.
4. The documentation must say what `prompt_detected` and `settled` actually do, including the
   cases where they are least useful.
