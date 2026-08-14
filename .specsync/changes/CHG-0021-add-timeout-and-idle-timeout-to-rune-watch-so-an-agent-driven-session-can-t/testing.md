---
change: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
artifact: testing
---

# Testing

- `PTYWatcher` with `timeout_seconds:` against a real long-running child (`sleep 10`, 1s timeout)
  kills it within a few seconds, reports exit code 124, `timed_out: true`, `timeout_kind: "timeout"`.
- `PTYWatcher` with `idle_timeout_seconds:` against a `sleep 10` child (no output ever) kills it
  and reports the same shape with `timeout_kind: "idle_timeout"`, and separately confirms a child
  that keeps producing output every 0.3s within a 2s idle window is *not* killed.
- `PTYWatcher` with neither option set produces a result data hash with no `timed_out`/
  `timeout_kind` keys at all — the regression guard for "no default behavior change."
- `WatchCommand#call`: `--timeout=N`/`--idle-timeout=N` parse and forward correctly (individually
  and combined); malformed values (`0`, negative, non-numeric, empty) are rejected before
  constructing `PTYWatcher`.
- Evidence to be filled in after implementation: `fledge run test`, `fledge run lint`,
  `fledge run spec-check` results.
