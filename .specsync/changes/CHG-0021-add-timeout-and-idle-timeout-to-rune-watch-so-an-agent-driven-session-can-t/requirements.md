---
change: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
artifact: requirements
---

# Requirements

- `rune watch --timeout=SECONDS <cmd>` kills the whole session (SIGKILL + reap) after `SECONDS`
  total wall-clock time and returns a successful `Result` with `data[:exit_code] == 124`,
  `data[:timed_out] == true`, `data[:timeout_kind] == "timeout"`.
- `rune watch --idle-timeout=SECONDS <cmd>` kills the session after `SECONDS` with no output from
  the child *and* no input from the human, same exit code/result shape, `timeout_kind: "idle_timeout"`.
- Both flags are independent and may be combined in one invocation.
- Neither flag changes the result data shape when it is not passed — no `timed_out`/`timeout_kind`
  keys appear, matching the existing envelope exactly (same additive-only principle as CHG-0020's
  `rune run --max-output`/`--tail`).
- Both flags follow the existing `--log`/`RunCommand --timeout` convention: recognized only before
  a `--` separator, malformed values (non-positive, non-numeric, empty) fail clearly before
  spawning anything.
- The NDJSON event log records which bound fired (`timeout` or `idle_timeout` event) in addition
  to the existing `start`/`output`/`exit` events.
