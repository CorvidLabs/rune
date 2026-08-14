---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: plan
---

# Plan

1. `PTYRunner#initialize` gains `separate_streams: false`. `#run` rejects `separate_streams: true`
   + `script:` up front with a clear `Result.failure`.
2. `execute_pty` dispatches via a new `spawn_for_mode` helper to either the existing
   `spawn_and_stream` or the new `spawn_and_stream_separate`, keeping the Timeout.timeout/kill+reap
   wrapper shared across both.
3. `spawn_and_stream_separate` (+ `spawn_with_separated_stderr` helper): `PTY.open` +
   `IO.pipe` + `Process.spawn(in:, out:, err:)`, reusing `SignalHandler.with_traps`, `write_input`,
   `wait_for_process` unchanged.
4. `read_separate_streams` (+ `poll_ready_streams`/`consume_stream_chunk` helpers): `IO.select`
   over `[{reader:, buffer:}, ...]`, each with its own `UTF8StreamDecoder`, appending to both the
   per-stream buffer and the shared `raw_output`.
5. `build_result_data` folds `clean_stdout`/`clean_stderr` into the result data only when
   `separate_streams` is set.
6. `RunCommand` gains `--separate-streams` in the existing flag extractor.
7. Update `specs/pty_runner/pty_runner.spec.md`: Public API, Invariants (including the
   controlling-terminal trade-off and the merged-view ordering caveat), Behavioral Examples, Error
   Cases, Change Log.
8. Tests: additions to `spec/rune/pty_runner_spec.rb` (real stream separation, exit code, timeout
   kill+reap, SIGINT forwarding, script: conflict, missing/non-executable command, and a
   no-default-change regression guard) and `spec/rune/commands/run_command_spec.rb` (flag
   parsing/forwarding).
9. `fledge run test`, `fledge run lint`, `fledge run spec-check`, then closing approval + accept.
