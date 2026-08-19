---
change: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
artifact: tasks
---

# Tasks

- [x] Reproduce the 127 misclassification with out-of-band proof that the child executed
- [x] Record `launch_failed` in the supervisor, only where exec actually failed
- [x] Read the fact in `launch_failure` instead of inferring it from the exit status
- [x] Keep the field absent rather than false, so older meta reads as a child that ran
- [x] Confirm a missing binary and a non-executable target both still fail loudly
- [x] Render idle time in hours and days past 90 minutes
- [x] Stop dimming a running session's idle time past `STALE_IDLE_SECONDS`
- [x] Leave a stopped session dim however long it has been quiet
- [x] Verify every new test against deliberately reverted code
