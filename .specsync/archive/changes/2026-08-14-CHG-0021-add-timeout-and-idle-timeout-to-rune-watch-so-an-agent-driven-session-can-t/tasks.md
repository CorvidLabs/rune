---
change: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
artifact: tasks
---

# Tasks

- [x] Add `timeout_seconds:`/`idle_timeout_seconds:` to `PTYWatcher#initialize`.
- [x] Add `run_with_timeout` (total wall-clock bound, `Timeout.timeout` + kill+reap).
- [x] Add idle-activity tracking (`@last_activity_at`) and the idle-timeout check inside
      `pump_output`'s poll loop; update it from both `emit_output` and `forward_input`.
- [x] Fold `timed_out`/`timeout_kind` into `build_result`'s data only when a bound fired.
- [x] Add `--timeout=SECONDS`/`--idle-timeout=SECONDS` to `WatchCommand`, replacing `extract_log`
      with a combined `extract_options`.
- [x] Update `specs/watch/watch.spec.md`.
- [x] Add RSpec coverage for both timeout kinds, the combined-flags case, and the
      no-default-change regression guard.
- [x] Run `fledge run test`, `fledge run lint`, `fledge run spec-check`.
