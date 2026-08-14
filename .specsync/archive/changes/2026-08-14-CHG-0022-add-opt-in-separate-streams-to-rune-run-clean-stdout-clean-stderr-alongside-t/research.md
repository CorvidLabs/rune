---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: research
---

# Research

- Ruby's `PTY.spawn` (used by the default single-stream path) does its controlling-terminal/
  session-leader setup natively in `ext/pty/pty.c` — `setsid` + attaching the pty as the child's
  controlling terminal — which is not reproducible from pure Ruby via `Process.spawn`. Splitting
  stdout (pty) from stderr (pipe) therefore requires bypassing `PTY.spawn` for the low-level
  `PTY.open` + `Process.spawn(in:, out:, err:)` API instead, which does *not* establish a true
  controlling terminal for the child.
- This project's own signal handling (`SignalHandler.with_traps`) already does not rely on
  terminal-driven job control — it explicitly re-forwards INT/TERM to the child's pid from ordinary
  polling code (see `pty_runner.rb`'s existing invariant #6), so the missing controlling-terminal
  semantics do not affect rune's own signal/timeout/kill machinery. Verified directly: real SIGINT
  forwarding and `--timeout` kill+reap both work identically in `separate_streams: true` mode
  (manual dogfooding — `bash -c 'sleep 10'` under both `Process.kill('INT', ...)` and a 1s
  `timeout_seconds`, and against a real `sleep 30` orphan-check via `Process.kill(0, child_pid)`
  after the fact).
- Manually verified the merged `clean_output`/`raw_output` view's chronological ordering across
  streams: exact when writes are spaced apart (beyond the ~0.2s poll interval), only
  select()-interval-approximate for near-simultaneous bursts on both streams — an inherent
  property of any two-file-descriptor split (also true of `subprocess.run`'s separate
  `stdout`/`stderr`, the baseline this feature is closing the gap with), not specific to this
  implementation. Documented explicitly rather than left implicit.
