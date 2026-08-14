---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: requirements
---

# Requirements

- `rune run --separate-streams <cmd>` adds `clean_stdout` and `clean_stderr` to the result data,
  each independently ANSI-stripped, alongside the existing merged `clean_output`/`raw_output`.
- Not passing `--separate-streams` leaves the result data byte-for-byte identical to today — no
  `clean_stdout`/`clean_stderr` keys appear.
- `exit_code`, `--timeout` kill+reap, and INT/TERM signal forwarding behave identically to the
  default single-stream mode.
- `separate_streams: true` combined with `script:` (Ruby API only — `RunCommand` never sets
  `script:`) fails clearly with `Result.failure` before spawning anything, rather than silently
  ignoring one or the other.
- `--separate-streams` follows the existing `--timeout` convention: recognized only before a `--`
  separator, may be combined with `--timeout` in the same invocation.
- The trade-off (the child no longer has a true controlling terminal/session-leader relationship —
  irrelevant to rune's own signal/timeout handling, but a child relying on terminal-driven job
  control itself would notice) is documented as the reason this is opt-in, not the default.
