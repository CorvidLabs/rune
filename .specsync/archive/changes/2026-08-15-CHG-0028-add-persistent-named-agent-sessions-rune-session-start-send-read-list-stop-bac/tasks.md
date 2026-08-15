---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: tasks
---

# Tasks

## Stage 1 — walking skeleton
- [x] `Session::Store`: `RUNE_HOME` resolution, `0700` dir + `0600` files, `meta.json` r/w, liveness
- [x] `Session::Supervisor`: `setsid`, `PTY.spawn`, `UNIXServer` accept loop, `output.ndjson` append
- [x] Hidden `session _supervise` entry point re-invoked via `Process.spawn`
- [x] `SessionCommand`: `start`, `send`, `stop`
- [x] End-to-end spec: persistence across separate invocations (**the gate — passed**)

## Stage 2 — send-and-settle
- [x] Cursor-at-send-time framing
- [x] `--settle-ms`, `--wait-for-regex`, `--timeout-ms`, `--no-wait`; `settled`/`timed_out` fields
- [x] Report `prompt_detected` as advisory metadata, never gating a reply
- [x] Shared last-non-blank-line prompt rule — **deferred, not done as planned.** Its honest home is
      `Parsers::PromptDetector`, which would pull the `parsers` spec and a `pty_runner.rb` edit into
      an already-large change; putting it under `Session::` while `PTYRunner` reached into it would
      be worse layering than the duplication it removes. `Session::PromptScanner` carries its own
      copy, recorded in the spec's Known Limitations rather than left silent.

## Stage 3 — read/list and lifecycle edges
- [x] `read` with `--since`/`--tail`/`--max-output` (reuses `OutputLimiter`), served from the
      durable transcript so it works for stopped sessions too
- [x] `list` with real liveness verification; `running` vs `exited`/`stopped` vs `dead`
- [x] Natural child exit: final `exit` event, `meta.json` state, supervisor exits
- [x] Idempotent `stop`; no-orphan assertions; failed `start` tears down the supervisor it spawned

## Stage 4 — surface and docs
- [x] `--help` via the `usage`/`flag` DSL for every subcommand
- [x] `specs/session/session.spec.md` canonical spec (delta applied at accept)
- [x] `docs/sessions.md` + README link
- [x] CHANGELOG entry
- [x] Dogfood against a real agent CLI; fold findings into documented limitations

## Found only by dogfooding (all fixed and pinned by regression tests)
- [x] The pty echoes input, so the settle clock started on the caller's own words and returned them
      as the "response" while the child was still thinking
- [x] Enter is carriage return, not line feed — with `\n` the prompt sat unsent in a real agent's
      composer while rune reported a clean settle
- [x] A detached pty has no window size, so full-screen TUI agents rendered into nothing
- [x] `sockaddr_un`'s 104-byte path cap breaks any deep `RUNE_HOME` (and every temp-dir test)
