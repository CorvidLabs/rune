# Agent Instructions — rune

## Overview

rune is a Ruby CLI that bridges terminal programs and AI agents, usable by humans and agents alike.
Zero runtime dependencies, stdlib only.

**Every command returns structured data.** Commands never print directly. They return a `Result`
that the `Renderer` formats for the context: a TTY gets human-pretty coloured output, a pipe or
`--json` gets JSON.

## The three execution models

| Model | What it is for |
|-------|----------------|
| `rune run` | One command, buffered, structured result. Does not stream. |
| `rune watch` | Live bidirectional passthrough. Requires a real terminal on stdin. |
| `rune session` | Named PTY sessions that outlive the invocation, driven by send-and-settle. |

`rune session` is the headline feature and the largest surface: `start`, `send`, `read`, `attach`,
`list`, `stop`, `archive`. A session's supervisor is detached (`Process.setsid`), owns the pty, and
serves a UNIX socket speaking newline-delimited JSON — so a non-Ruby client can drive it directly.

## Running tasks (use fledge)

```sh
fledge run test          # RSpec
fledge run lint          # RuboCop
fledge lanes run verify  # full CI gate
fledge lanes run release # adds smoke tests and the gem build
fledge lanes run fix     # auto-format, then lint
```

## The change lifecycle is not optional

Every meaningful change needs a spec-sync change record, or CI fails with *"meaningful changed paths
are not covered by an active change"*.

```sh
specsync change new "<title>"                    # then answer the interview
specsync change approve <id>                     # AFTER the delta is final
specsync change start <id>
specsync change verify <id>                      # runs the gates
specsync change accept <id> --actor <you>
```

Three things that will cost you an hour each if you learn them the hard way:

- **The delta is part of the definition digest.** Approve only after the delta is final, or approve
  again after regenerating it.
- **`verify` and `accept` must be the last thing before committing**, and never `git commit --amend`
  afterwards — it orphans the recorded verification commit.
- **`specsync change verify` checks one change; `specsync check` checks the lifecycle.** Only the
  second catches a shared file staling every other accepted change. Run it before pushing.

Touching `README.md`, `CHANGELOG.md` or a shared spec stales every accepted change that lists it,
and each needs an audited reopen plus a full suite run. Archive accepted changes rather than leaving
them active — measured, reopenings correlate with record size at r=0.949.

## Adding a command

1. `lib/rune/commands/your_command.rb`, extending `Rune::Command`
2. Define `name`, `summary`, `call`, `human_render`
3. `require_relative` in `lib/rune.rb`
4. Tests in `spec/rune/commands/your_command_spec.rb`
5. Document every export in the module's `specs/*.spec.md` — coverage is gated at 100%

## Architecture rules

- Zero external runtime dependencies. Stdlib only.
- Every command works in both human and agent mode.
- Every public module has a spec-sync contract.
- The supervisor's event loop is single-threaded: anything slow there starves the pty drain.

## How work is judged here

This project has a specific, earned standard. It is worth internalising before proposing anything.

**Measure, do not assert.** Every performance and behaviour claim in the changelog has numbers
behind it. Claims without measurement have been wrong more often than the code.

**Go looking for the case your fix loses.** Every bad fix in this repository passed its author's own
measurements first. One settle fix scored 12/12 on the failing cases and was reverted for breaking a
child whose reply ends with the request.

**An unproven fix is worse than a documented limitation.** Two candidate fixes have shipped as
documented limitations because they could not be validated; one measured *worse* than doing nothing.
Reporting that you could not validate something is a valuable outcome, not a failure.

**Your harness is probably wrong before the code is.** Confirmed harness errors in this repo: a
nonce matching its own echo; `PTY.spawn` ignoring `chdir:`; zsh's `echo` interpreting backslash
escapes and corrupting captured JSON; a substring matching an unrelated hint; reading a display-only
field and diagnosing quoting from it. Control for the alternative explanation before reporting.

**A test that cannot fail is worse than no test.** Verify a new regression test against deliberately
broken code. One was deleted here for passing with the fix reverted.

**References are not oracles.** `pyte` has been wrong four times against rune (no SU, no DECSTR, no
`CSI u`, and it prints the final byte of a private-marker CSI). Where a reference disagrees, decide
from ECMA-48 or xterm's source before changing anything.

## Known limitations to respect

- **`--settle-ms` can return the caller's own input** when the child redraws it (`irb`, `python3`).
  Four rules have been measured and rejected; `ROADMAP.md` records each and why. Use
  `--wait-for-regex` for a repainting REPL.
- **`rune run` does not forward its own stdin.** Put redirects inside the command:
  `rune run -- sh -c 'cmd < file'`.
- **The `command` field in a reply is a display reconstruction**, shell-escaped for humans. It is
  not what the child received. Do not diagnose quoting from it.

## Provenance

`.trust.toml` records `provenance.mode = "off"` with the reason. **Do not run `attest sign` or add a
provenance gate** — the managed block below predates that decision and its Attest line no longer
applies. Everything else in it stands.

<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge trust verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->
