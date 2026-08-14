---
id: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
state: verifying
type: feature
base_commit: 451a5752b135c54a2324c61f087eacb2bd79252d
---

# Add persistent named agent sessions: rune session start/send/read/list/stop, backed by a per-session detached supervisor holding the PTY, with send-and-settle so one agent CLI can drive another synchronously

## Intent

Add persistent named agent sessions: rune session start/send/read/list/stop, backed by a per-session detached supervisor holding the PTY, with send-and-settle so one agent CLI can drive another synchronously

## Affected Canonical Specs

- `session`
- `cli`
- `parsers`

## Acceptance Criteria

- A named session survives across separate rune invocations: 'rune session start --name s -- bash' returns, the rune process exits, and a later 'rune session send --name s "echo hi"' returns 'hi' from that same still-running child. send-and-settle returns only output produced after that send (cursor taken at send time), blocking until the child is quiet for --settle-ms, or --wait-for-regex matches, or --timeout-ms caps it (reporting settled:false, timed_out:true). 'rune session list' reports live vs dead sessions, distinguishing a supervisor that died without cleanup. 'rune session stop' kills and reaps both child and supervisor and leaves no orphan. All commands work in --json agent mode with parseable stdout. Session state lives under RUNE_HOME (default ~/.rune) with owner-only 0700 dirs and 0600 files. The full transcript is an NDJSON event log in the same format rune watch already writes, so 'tail -f' works.

## No-spec Rationale

Not applicable
