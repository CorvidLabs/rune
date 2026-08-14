---
change: CHG-0027-fix-too-tight-1s-timeout-margin-in-a-pty-runner-spec-rb-prompt-detected-test
artifact: tasks
---

# Tasks

- [x] `timeout_seconds: 1` -> `3` in the `--timeout` + `prompt_detected` test; child sleep bumped
      from 5 to 10 seconds to keep well beyond the new timeout.
- [x] Add the same defensive comment style already used by the neighboring orphan-process
      timeout test.
- [x] Confirm the test passes in isolation and no longer flakes under load.
