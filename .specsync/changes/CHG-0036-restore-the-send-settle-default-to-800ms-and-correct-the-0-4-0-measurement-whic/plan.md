---
change: CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic
artifact: plan
---

# Plan

1. Notice that the settle measurement used a prompt length that the submit bug affected.
2. Re-run it for claude with submission fixed.
3. Notice the grok figures had a different fault — byte-stream detection — and fix the harness to
   read the rendered screen.
4. Re-run for grok and agy; discard agy on the impossible-ordering check.
5. Restore the default and correct every place the old figures were recorded.
