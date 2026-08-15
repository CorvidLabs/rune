---
change: CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic
artifact: context
---

# Context

0.4.0 raised the send settle default from 800ms to 3000ms and recorded the measurement behind it in
the spec, the changelog and the constant's own comment. Fixing the unsubmitted-prompt bug in this
same branch invalidated that measurement, so it had to be re-run.

Both of the original harnesses reproduced the very bugs they were meant to be independent of. The
claude figures used an 84-character prompt, above the ~64-character threshold at which nothing was
being submitted at all, so what looked like "settle returned the previous turn's answer" was
"this turn never happened and the screen still showed the previous one". The grok figures searched
the raw byte stream for the answer, where repaints had split it — the same defect `--screen` was
built to fix.

A wrong number in a shipped default is recoverable. A wrong number presented as measured, in a spec
that other decisions will be built on, is worse.
