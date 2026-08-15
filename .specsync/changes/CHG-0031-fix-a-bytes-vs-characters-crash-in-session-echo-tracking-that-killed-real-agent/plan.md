---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: plan
---

# Plan

1. Add crash reporting and the teardown guarantee, so the failure can be diagnosed at all.
2. Reproduce against agy, read the backtrace, fix both bytes-vs-characters sites.
3. Re-run the reproduction to confirm the session survives.
4. Raise the settle default to the measured value and report `busy_at_send`.
5. Record the measurements in Known Limitations, replacing the claim that described the wrong
   failure.
