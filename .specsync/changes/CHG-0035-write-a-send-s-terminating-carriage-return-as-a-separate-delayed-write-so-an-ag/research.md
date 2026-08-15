---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: research
---

# Research

Bisected by length against Claude Code, holding the instruction constant and varying only filler:

| chars | before | after |
|-------|--------|-------|
| 61    | yes    | yes   |
| 82    | **no** | yes   |
| 102   | **no** | yes   |
| 122   | **no** | yes   |
| 142   | **no** | yes   |
| 182   | **no** | yes   |
| 262   | **no** | yes   |

Three ways of writing the same 110-character prompt, before the fix:

| how | submitted |
|-----|-----------|
| text and CR in one write | no |
| text, pause, CR as its own write | yes |
| text in 8-character pieces, then CR | yes |

That isolates the cause to the size of the chunk delivered in one read, not to the content, the
length of the composer, or the terminator itself.

grok and agy submit 7/7 both before and after, so the fix costs them nothing.

One earlier attempt at this measurement was invalid: run from an untrusted directory, claude showed
a first-run trust dialog that swallowed the input, and every case looked like a failure. Re-run from
the repo, which is already trusted.
