---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: research
---

# Research

Line counts before and after:

| file | before | after |
|------|--------|-------|
| `lib/rune/session/supervisor.rb` | 980 | 815 |
| `lib/rune/session/pending_send.rb` | — | 191 |

The first attempt at this extraction was done with regular-expression surgery over the whole file
and produced a syntax error by deleting across block boundaries; it was reverted rather than
patched, and redone with explicit edits and a syntax check after each step.
