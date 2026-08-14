---
change: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
artifact: plan
---

# Plan

1. `PTYWatcher#initialize` gains `timeout_seconds:`/`idle_timeout_seconds:` keyword args (default
   `nil`; both `nil` reproduces current behavior exactly).
2. `run_session` wraps the existing `with_raw_input { pump_session(...) }` call in a new
   `run_with_timeout(pid) { ... }` helper: a no-op passthrough when `timeout_seconds` is unset,
   otherwise `Timeout.timeout(timeout_seconds) { ... }`, rescuing `Timeout::Error` to kill+reap the
   child (reusing `terminate_child`) and return exit code 124 — same shape as `PTYRunner`'s
   existing timeout handling.
3. `pump_output`'s loop tracks `@last_activity_at` (updated on every non-empty output chunk in
   `emit_output`, and from `forward_input`'s background thread on every input chunk read from the
   human) and checks it once per poll iteration; when `idle_timeout_seconds` has elapsed since the
   last activity, kill+reap the child and return exit code 124.
4. `build_result` folds `timed_out`/`timeout_kind` into the result data only when a bound actually
   fired.
5. `WatchCommand` gains a combined argv extractor (`extract_options`, replacing `extract_log`)
   covering `--log=PATH` (existing), `--timeout=SECONDS`, `--idle-timeout=SECONDS` — validated as
   positive integers, same convention as `RunCommand`'s `--max-output`/`--tail` extractor.
6. Update `specs/watch/watch.spec.md`: Public API, Invariants, Behavioral Examples, Error Cases,
   Change Log.
7. Tests: additions to `spec/rune/pty_watcher_spec.rb` (real `--timeout`/`--idle-timeout` firing,
   and a regression guard that an ordinary session's result data is unchanged) and
   `spec/rune/commands/watch_command_spec.rb` (flag parsing/validation/forwarding).
8. `fledge run test`, `fledge run lint`, `fledge run spec-check`, then closing approval + accept.
