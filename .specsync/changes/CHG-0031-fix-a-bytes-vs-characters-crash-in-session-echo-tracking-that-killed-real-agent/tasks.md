---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: tasks
---

# Tasks

- [x] `crashed` logs a crash event and stderr, finishing with EXIT_SUPERVISOR_CRASHED
- [x] teardown finishes the session when `finish` never ran
- [x] `echo_still_arriving?` bounds its loop by character length
- [x] `beyond_echo` advances past the echo by character length
- [x] `DEFAULT_SETTLE_MS` raised to 3000 and the flag help updated
- [x] `busy_at_send` recorded at send time and reported in the settle reply
- [x] regression tests for each, plus the crash-reporting contract
- [x] Known Limitations rewritten with the measured numbers
