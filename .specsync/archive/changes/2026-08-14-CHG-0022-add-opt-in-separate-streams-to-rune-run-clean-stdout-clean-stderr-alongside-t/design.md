---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: design
---

# Design

- `PTYRunner` gains `separate_streams: false`. When true, `execute_pty` dispatches to
  `spawn_and_stream_separate` instead of the existing `spawn_and_stream`.
- `spawn_and_stream_separate`: `PTY.open` for the stdout+stdin pty pair (`master`/`slave`),
  `IO.pipe` for stderr (`err_r`/`err_w`), `Process.spawn(env, *argv, in: slave, out: slave, err:
  err_w)`, closing the child-side descriptors in the parent immediately after spawn (the standard
  pty-pattern for correct EOF detection). `SignalHandler.with_traps`, `write_input`, timeout
  kill+reap, and exit-code reaping are all reused unchanged from the existing single-stream path.
- `read_separate_streams` multiplexes `master` (stdout) and `err_r` (stderr) with `IO.select` on
  the same ~0.2s cadence `read_pty_stream` already polls at (rather than the single
  `#wait_readable` used for one stream), each with its own `UTF8StreamDecoder` so a multi-byte
  character split across a read boundary on one stream is never corrupted by interleaving with the
  other. Each stream is appended to its own buffer *and* to the shared `raw_output`, so the merged
  `clean_output`/`raw_output` view keeps working exactly as before.
- `#run` refuses (`Result.failure`) to combine `separate_streams: true` with `script:` — the
  interactive `wait_for`/`send_keys` DSL is only meaningful against one stream, and `RunCommand`
  never sets `script:` from the CLI at all, so this only matters for direct Ruby API callers.
- Fully additive: `clean_stdout`/`clean_stderr` only appear in the result data when
  `separate_streams: true` was actually requested; the default result shape is unchanged.
- `RunCommand` gains `--separate-streams` (boolean, no value) in the same `extract_flags`
  extractor `--timeout` already uses, following the same before-`--`-only convention.
