---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: research
---

# Research

## Where agent mode is decided today

`Renderer#agent_mode?` is `json_mode || ndjson_mode || !io.tty?`. That decision lives entirely
inside the renderer and is made *after* the command has already run, so a command that produces
side-effect output during `#call` cannot currently consult it. `CLI#run_command` does already pass
`{ json:, ndjson: }` into `Command#call`, and `WatchCommand` ignores it as `_options` — the flag
half of the signal is available, unused.

The pipe half is not: `Renderer` is constructed with the CLI's injected `io`, which the tests
replace with a `StringIO`. A command cannot reach that object. Since `PTYWatcher`'s live stream is
by definition the process's real terminal, testing `$stdout.tty?` directly in the command is both
correct and the only option that does not require threading the renderer through `Command#call`.

## Where the live stream should go in agent mode

Three options were considered.

1. **Suppress the display entirely.** Rejected: it destroys the feature's whole premise. A human is
   still driving the session even when a wrapping process captures stdout.
2. **Write it to the NDJSON log only.** Rejected for the same reason, and it makes
   `rune watch --json` behave unlike `rune watch` for the human at the keyboard.
3. **Write it to stderr.** Chosen. It is the conventional destination for a stream that is not the
   program's structured result, it keeps the live view visible whenever stderr is still a terminal,
   and it composes: `rune watch --json -- cmd 2>/dev/null | jq` yields clean JSON, while
   `rune watch --json -- cmd > result.json` still shows the human their session.

`WatchCommand` already writes its log-path announcement to stderr for exactly this reason, so this
extends an established convention rather than inventing one.

## Attest forwarding

`CorvidLabs/attest@1.0.0` exposes `forward-from`, `forward-to`, `forward-reviewer`, and
`forward-sign` inputs, and the CLI exposes a matching `attest forward` subcommand described as
"Record a fresh attestation on a landed commit from an already-attested source commit". The squash
merge case is precisely what they exist for. The reviewed head SHA for a landed commit is
recoverable on a `push` event via `GET /repos/{repo}/commits/{sha}/pulls`, selecting the pull
request whose `merge_commit_sha` equals the pushed SHA. That endpoint needs `pull-requests: read`,
which the trust job does not currently request.
