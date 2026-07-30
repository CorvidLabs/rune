---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: tasks
---

# Tasks

- [x] T1 `lib/rune/commands/watch_command.rb`: add `display_stream`/`agent_mode?` and pass
      `output:` into `PTYWatcher`.
- [x] T2 `spec/rune/commands/watch_command_spec.rb`: four stream-routing examples plus a guard that
      the human TTY path still receives `$stdout`.
- [x] T3 `spec/rune/e2e_spec.rb`: stdout-purity group over every command x every agent mode,
      including `watch` under a real pty.
- [x] T4 `specs/watch/watch.spec.md`: new invariant, new API rows, change-log entry.
- [x] T5 `specs/cli/cli.spec.md`: state the stdout-purity guarantee on invariants 3 and 4.
- [x] T6 `.github/workflows/ci.yml`: range resolution, empty-range rejection, attest forwarding,
      `pull-requests: read`.
- [x] T7 `scripts/trust_range.sh` + `fledge.toml`: local range parity.
- [x] T8 `README.md` / `CHANGELOG.md`: document the agent-mode stream split; fix the stale
      "160 examples" figure.
- [x] T9 Verification: `fledge lanes run verify`, `fledge run smoke-test`, manual repro of both
      defects before and after.
