---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: testing
---

# Testing

## The hard part

These are the first tests in this repo against **detached, out-of-process** children. The existing
PTY specs all run in-process, so the whole "reap it in an `ensure`" discipline is new here. A
leaked supervisor in CI is the failure mode to design against from the start, not to discover.

Rules for every session spec:

- `RUNE_HOME` is pointed at a `Dir.mktmpdir` per example — no spec ever touches a real `~/.rune`.
- Every example that starts a session stops it in an `ensure`/`after` hook, and the hook tolerates
  an already-dead session (stop is idempotent by requirement R7).
- A final suite-level sweep asserts no supervisor from the temp `RUNE_HOME` is still alive.
- Waits are condition-polled, never fixed `sleep`s. This repo has been bitten repeatedly by
  timing-tuned tests (CHG-0027, and the SIGINT/demo_tui race before it); poll for the observable
  condition instead of guessing a margin.

## Coverage

| Area | What is asserted |
|---|---|
| Persistence (the core claim) | Start a session, let the launching process exit, then send from a *separate* invocation and get output back from the same child. This is the one test that proves the feature exists. |
| Send framing | Output produced *before* the send is never attributed to it (cursor-at-send-time). |
| Settle | Returns on quiet; returns early on `--wait-for-regex`; returns capped with `settled:false, timed_out:true` on `--timeout-ms`. |
| Prompt metadata | `prompt_detected` is reported but does **not** gate the return — asserted explicitly against a child with no shell-shaped prompt, which is the realistic agent-CLI case. |
| Lifecycle | Child exits on its own → final `exit` event + `meta.json` updated + supervisor exits. `stop` is idempotent. `list` reports `dead` for a supervisor killed without cleanup. |
| Security | Session dir is `0700`; `meta.json`/`output.ndjson`/`control.sock` are `0600`. |
| Agent mode | Every subcommand's complete stdout parses as a single JSON document, joining the existing end-to-end stdout-purity assertion. |
| Transcript | `output.ndjson` events match the vocabulary `PTYWatcher` already emits. |

## Known limits of this suite

Settle behavior is validated against synthetic children with controlled output timing. It cannot
prove the default `--settle-ms` is right for a real agent CLI — only dogfooding can, and the plan
treats that as a separate validation step whose findings feed the spec's documented limitations.
