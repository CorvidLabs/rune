---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: tasks
---

# Tasks

- [x] establish the failure is unsubmitted input, not settle timing or rendering
- [x] bisect the length boundary
- [x] isolate chunk size as the cause
- [x] `SUBMIT_DELAY`, `schedule_submit`, `deliver_submit`, `flush_submit`
- [x] regression test on read boundaries, verified failing against the unfixed code
- [x] re-run the bisect on claude, grok and agy
