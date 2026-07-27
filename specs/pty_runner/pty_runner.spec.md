---
module: pty_runner
version: 1
status: active
files:
  - lib/rune/pty_runner.rb
  - lib/rune/commands/run_command.rb
---
# PTY Runner

## Purpose
Pseudo-Terminal (PTY) runner and text sanitizer for `rune`. Spawns un-structured TTY CLI commands in a sandboxed PTY process, cleans ANSI formatting, tracks execution timing, and exposes structured execution contracts to AI agents and humans alike.

## Public API
| Name | Type | Description |
|------|------|-------------|
| `PTYRunner` | class | Spawns command in PTY. Constructor: `(command, input: nil, script: nil, timeout_seconds: 30, &on_output)`. Method: `#run` returns `Result`. Class method: `.pty_available?` reports whether the `pty` stdlib loaded successfully. |
| `RunCommand` | class | Subcommand `rune run [--timeout=SECONDS] <command...>` exposing PTY process runner to humans and agents. `--timeout` overrides the default 30s PTYRunner timeout; only recognized before a `--` separator; must be a positive integer or the command fails with a clear error instead of leaking the raw flag into the executed command. |

## Invariants
1. Executed commands run inside a PTY session so TTY-dependent CLIs behave naturally.
2. Output is stripped of ANSI escape sequences before being returned in `clean_output`.
3. Duration of process execution is measured and returned in milliseconds.
4. The command's own exit code is always returned in `data[:exit_code]`, and the `Result` itself
   is `success` (the run was captured) even when the wrapped command's exit code is non-zero.
5. `Result#exit_code` (the process-level exit status `rune run` itself exits with) mirrors the
   wrapped command's exit code, not the `success`/`failure` status of the `Result` — so `rune run
   -- false` composes correctly with shell `&&`/`||`/`set -e` even though the `Result` succeeded.
6. INT/TERM received by the `rune run` process are forwarded to the wrapped child so it terminates
   promptly instead of running to completion; forwarding happens from ordinary code polling between
   reads, never from inside the signal trap itself (see `lib/rune/signal_handler.rb`).
7. If the `pty` stdlib failed to load (e.g. unsupported platform), `#run` returns a structured
   failure immediately instead of raising `NameError`/`LoadError`; other rune commands (`version`,
   `help`) remain usable regardless.
8. If the `pty` stdlib loaded but the OS refuses to allocate a pty at runtime (`Errno::ENXIO`,
   `EMFILE`, `ENFILE`, `EPERM` — e.g. a sandbox/container denying it, or pty exhaustion), `#run`
   returns a structured failure instead of raising. This is distinct from `Errno::ENOENT`/`EACCES`
   raised by exec'ing the *target* command, which remain ordinary exit codes (127/126) in
   `data[:exit_code]` on a successful `Result`, since those describe the wrapped command, not rune's
   own environment.

## Behavioral Examples
- `ruby bin/rune run -- echo "Hello PTY"` outputs clean JSON in agent mode (`--json`) containing `exit_code: 0`, `clean_output: "Hello PTY\n"`, and `duration_ms`.
- `rune run -- nonexistent_binary` returns a *successful* `Result` with `data[:exit_code]: 127`; the `rune` process itself also exits `127`.
- `rune run -- bash -c "exit 7"` — `rune run` (no `--json`) exits `7` at the shell, even though the `Result` is a success.
- `rune run --timeout=5 -- sleep 30` overrides the default 30s timeout and returns exit code 124 after ~5 seconds.
- `rune run --timeout=0 -- echo hi` fails fast with `Result.failure("Invalid --timeout value...")` instead of silently disabling the timeout (Ruby's `Timeout.timeout(0)` means "no timeout", not "instant timeout").

## Error Cases
| Condition | Behavior |
|-----------|----------|
| No command argument | Returns `Result.failure("No command specified...")` |
| Command times out | Returns exit code 124 with timeout message in output |
| `--timeout` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --timeout value...")` before spawning anything |
| `pty` stdlib failed to load | `PTYRunner#run` returns `Result.failure("PTY unavailable: ...")` |
| OS refuses pty allocation at runtime (sandbox/container/exhaustion) | `PTYRunner#run` returns `Result.failure("PTY allocation failed at runtime: ...")` |

## Dependencies
- Ruby stdlib: `pty`, `timeout`

## Change Log
- v1: Active PTY runner spec contract
