---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: tasks
---

# Tasks

- [x] Add `separate_streams:` to `PTYRunner#initialize`; reject it combined with `script:`.
- [x] `spawn_and_stream_separate`/`spawn_with_separated_stderr` (PTY.open + IO.pipe +
      Process.spawn).
- [x] `read_separate_streams`/`poll_ready_streams`/`consume_stream_chunk` (IO.select multiplexing,
      per-stream decoders).
- [x] `build_result_data` folds in `clean_stdout`/`clean_stderr` only when requested.
- [x] Add `--separate-streams` to `RunCommand`.
- [x] Update `specs/pty_runner/pty_runner.spec.md`.
- [x] Add RSpec coverage (separation, exit code, timeout, SIGINT, script: conflict, missing/
      non-executable command, no-default-change regression guard, CLI flag parsing/forwarding).
- [x] Manual real-terminal dogfooding: stream separation, chronological-ordering sanity check
      (spaced vs. bursty writes), timeout kill+reap with orphan check, SIGINT forwarding.
- [x] Run `fledge run test`, `fledge run lint`, `fledge run spec-check`.
