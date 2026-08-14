---
change: CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e
artifact: tasks
---

# Tasks

- [x] Add a private `prompt_detected_in?(text)` computing the answer from the last non-blank
      line of `text`.
- [x] Compute `prompt_detected` once in `execute_pty`, from `raw_output`, on every return path
      (success, `PTY::ChildExited`, and `--timeout`) instead of threading an accumulator through
      the read loop.
- [x] Remove the now-unnecessary `prompt_found`/`prompt_detected` parameters and return values
      from `spawn_and_stream`, `spawn_and_stream_separate`, `read_pty_stream`,
      `consume_output_chunk`, `read_separate_streams`, `poll_ready_streams`,
      `consume_stream_chunk`, `append_decoded_chunk`.
- [x] Update `specs/pty_runner/pty_runner.spec.md` (Invariants, Behavioral Examples).
- [x] Add RSpec coverage: last-line-only detection (a mid-run prompt-shaped line followed by more
      real output no longer trips it), a genuinely trailing prompt still trips it, and the
      `--timeout` case now reflects real content instead of being hardcoded `false`.
- [x] Run `fledge run test`, `fledge run lint`, `fledge run spec-check`.
