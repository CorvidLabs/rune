---
change: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
artifact: requirements
---

# Requirements

1. `start` fails only when exec itself failed, established by the supervisor rather than inferred
   from the child's exit status.
2. A child that runs and then exits 127 is a successful start.
3. A missing binary (`ENOENT`) and a target that exists but cannot be executed (`EACCES`) are both
   reported as failures.
4. `launch_failed` is absent rather than false when a child ran, so meta written by an earlier
   version reads as a child that ran.
5. `session list` renders a running session's idle time in a unit a reader does not have to convert:
   seconds, minutes, hours, then days.
6. A running session whose silence exceeds `STALE_IDLE_SECONDS` is not dimmed.
7. A stopped session's idle time stays dim however long it has been quiet.
8. Nothing here claims to detect that a session is stuck.
