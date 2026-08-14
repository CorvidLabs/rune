---
change: CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t
artifact: context
---

# Context

Issue #14: there is no timeout anywhere in the `rune watch` path. `PTYRunner` has
`timeout_seconds:` (default 30) and `--timeout`; `PTYWatcher` has neither — `pump_output` polls
`reader.wait_readable(0.2)` in an unbounded loop until the child's stream ends. For interactive
human use that is correct (nobody wants a session killed out from under them), but `rune watch` is
explicitly documented as an agent-facing feature ("so an AI agent can tail the session live"), and
an agent that invokes it on a child which never exits hangs forever with no recovery path.

This change adds both suggested bounds from the issue: `--timeout=SECONDS` (total wall-clock,
reusing `PTYRunner`'s proven `Timeout.timeout` + explicit kill+reap pattern) and
`--idle-timeout=SECONDS` (no output *and* no input for N seconds — checked cooperatively inside
`pump_output`'s existing 0.2s poll loop, since an idle window can't be expressed as a single
`Timeout.timeout` deadline). Both default to unset, preserving today's unbounded interactive
behavior exactly; both may be combined.
