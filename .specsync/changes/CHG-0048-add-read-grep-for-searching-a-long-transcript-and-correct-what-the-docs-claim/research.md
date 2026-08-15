---
change: CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim
artifact: research
---

# Research

`prompt_detected`, measured against real output rather than read off the source:

| last line | result |
|-----------|--------|
| `plain output` | false |
| `$ ` | false |
| `Do you want to proceed? ` | **false** |
| `❯ ` | **true** |

So the reporter's "true 8 times out of 8" was correct for their callee and their conclusion — that
it discriminates nothing — was not. It discriminates; it is answering a different question than the
one they needed, and it answers it backwards for the dialog case.

Two hypotheses about the repaint race were tested and discarded: that comparing consecutive renders
would yield a stable frame (measured 13 torn frames out of 20 against 11 for the status quo), and
that the renderer's tail window could drop a screen clear and leave stale content (impossible by
construction — a cut that removes the clear removes the content before it as well).
