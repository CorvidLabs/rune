---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: plan
---

# Plan

Staged so the **riskiest assumption is proven first**. The architecture (detached supervisor +
socket control channel) is the part most likely to be wrong, so stage 1 is a walking skeleton that
exercises it end-to-end against a trivial child before any polish is invested.

## Stage 1 — Walking skeleton (proves the architecture)

Smallest path that demonstrates persistence across invocations:

- `Session::Store` — `RUNE_HOME` resolution, session dir creation with `0700`/`0600`, `meta.json`
  read/write, liveness check.
- `Session::Supervisor` — `setsid`, `PTY.spawn`, `UNIXServer` accept loop, append to
  `output.ndjson`, handle `send`/`status`/`stop`.
- `SessionCommand` — `start`, `send` (no settle yet, fixed short wait), `stop`.
- One end-to-end spec: start `bash`, exit the parent, send `echo hi`, assert `hi` comes back from
  the *same* child, stop, assert no orphan.

**Gate:** if this does not work reliably, the design is wrong and we revisit before building more.

## Stage 2 — Send-and-settle (the primitive that matters)

- Cursor-at-send-time framing so only post-send output is returned.
- `--settle-ms`, `--wait-for-regex`, `--timeout-ms`, `settled`/`timed_out` reporting.
- Extract the last-non-blank-line prompt rule out of `PTYRunner#prompt_detected_in?` into a shared
  home; both call sites use it. Report `prompt_detected` as advisory metadata.

## Stage 3 — Read / list, and the lifecycle edges that will actually bite

- `read` with `--since`/`--tail`/`--max-output`, reusing `OutputLimiter`.
- `list` with real liveness verification; `dead` vs `running`; stale-state handling.
- Child exits on its own → final `exit` event, `meta.json` state updated, supervisor exits cleanly.
- Idempotent `stop`; `stop` on an already-dead session; supervisor killed out from under a live
  child.

## Stage 4 — Surface and docs

- `--help` text via the existing `usage`/`flag` DSL for every subcommand.
- `specs/session/session.spec.md` written as the canonical spec (delta applied at accept).
- `docs/` page showing the real agent-driving-agent loop, with genuine captured output.
- CHANGELOG entry.

## Verification at each stage

`fledge run lint`, `fledge run test`, then `fledge run spec-check` / `spec-lifecycle` before
accept. Full `fledge lanes run verify` before opening the PR.

## Dogfooding

The real validation is stage 2 driving an actual agent CLI, not a synthetic child — that is the
only way to learn whether the default `--settle-ms` is sane and whether `--wait-for-regex` is
needed in practice. Findings feed back into the spec's documented limitations.
