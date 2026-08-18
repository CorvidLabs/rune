---
change: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
artifact: tasks
---

# Tasks

- [x] Verify all three, including re-testing watch through a real PTY
- [x] `Command.flag_error` shared by run and watch
- [x] `Transcript.grep_text`; `filter` searches the slice
- [x] `bound_stream` for clean_stdout/clean_stderr
- [x] Tests for all three, each falsified
- [x] Follow the moved exports through the specs
- [x] Invariants: watch 20, pty_runner 29, session 41p
