---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: requirements
---

# Requirements

## Functional

| # | Requirement |
|---|---|
| R1 | `rune session start --name <n> -- <cmd...>` spawns `<cmd>` under a PTY held by a detached supervisor, and returns immediately. The child survives the launching `rune` process exiting *and* the launching terminal closing. |
| R2 | `rune session send --name <n> <text>` writes `<text>` (plus a trailing newline unless `--no-newline`) to the session's PTY and returns **only output produced after that send**, using a cursor taken at send time. |
| R3 | Send blocks until whichever comes first: no new output for `--settle-ms` (default 800), `--wait-for-regex` matches, or `--timeout-ms` (default 120000) elapses. |
| R4 | A `--timeout-ms` cap returns the output captured so far with `settled: false, timed_out: true` rather than failing. |
| R5 | `rune session read --name <n> [--since=CURSOR] [--tail=N] [--max-output=BYTES]` returns transcript output plus the new cursor, without sending anything. |
| R6 | `rune session list` reports every session with its state, distinguishing `running` from `dead` by verifying process liveness, not by trusting `meta.json`. |
| R7 | `rune session stop --name <n>` kills and reaps both the child and the supervisor, leaving no orphan, and is idempotent against an already-dead session. |
| R8 | Every subcommand works in agent mode (`--json`/`--ndjson`) with stdout that parses as a single JSON document. |
| R9 | `prompt_detected` is reported on `send`/`read` results as advisory metadata; it never gates whether a call returns. |

## Non-functional

| # | Requirement |
|---|---|
| N1 | **Zero new runtime dependencies.** Ruby stdlib only (`socket` is the one new stdlib require). |
| N2 | Session dirs are `0700`; `meta.json`, `output.ndjson`, and `control.sock` are `0600` — matching the existing watch-log security precedent. |
| N3 | The transcript uses the **same NDJSON event vocabulary `PTYWatcher` already writes**, so one format serves both features and `tail -f` works. |
| N4 | State lives under `RUNE_HOME` (default `~/.rune`), overridable so tests never touch a real user's state. |
| N5 | Existing `rune run` / `rune watch` behavior and result shapes are **unchanged**. This is purely additive. |
| N6 | No test may leak a supervisor or child process; every spec reaps in an `ensure`/`after` hook. |

## Explicit non-goals for this change

- **Per-agent profiles** (built-in knowledge of codex/grok/claude prompt shapes). Deferred
  deliberately: it bakes in per-vendor detail that ages badly before real dogfooding tells us what
  is actually needed. `--wait-for-regex` covers the same ground generically.
- **Cross-session routing / a message bus.** rune stays a session *broker*; deciding who talks to
  whom is the calling agent's job. Building routing in would make rune a framework rather than a
  thin transparent wrapper.
- **A tmux backend.** Viable later as an optional backend; not v1.
- **Windows support.** rune already requires PTY; Unix sockets keep the same constraint.
