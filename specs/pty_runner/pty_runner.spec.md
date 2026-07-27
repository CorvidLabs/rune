---
module: pty_runner
version: 1
status: active
files:
  - lib/rune/pty_runner.rb
  - lib/rune/commands/run_command.rb
  - lib/rune/script.rb
---
# PTY Runner

## Purpose
Pseudo-Terminal (PTY) runner and text sanitizer for `rune`. Spawns un-structured TTY CLI commands in a sandboxed PTY process, cleans ANSI formatting, tracks execution timing, and exposes structured execution contracts to AI agents and humans alike.

## Public API
| Name | Type | Description |
|------|------|-------------|
| `PTYRunner` | class | Spawns command in PTY. Constructor: `(command, input: nil, script: nil, timeout_seconds: 30, &on_output)`. Method: `#run` returns `Result`. Class method: `.pty_available?` reports whether the `pty` stdlib loaded successfully. |
| `RunCommand` | class | Subcommand `rune run [--timeout=SECONDS] <command...>` exposing PTY process runner to humans and agents. `--timeout` overrides the default 30s PTYRunner timeout; only recognized before a `--` separator; must be a positive integer or the command fails with a clear error instead of leaking the raw flag into the executed command. |
| `Script` | class | Interactive step DSL passed to `PTYRunner.new(script:)`. Constructor: `Script.new(&block)` (or `Script.define(&block)`, an alias) evaluates the block via `instance_eval`, so DSL methods can be called bare inside it. DSL methods: `wait_for(pattern)`, `send_keys(keys)`, `pause(seconds)` — each appends a `Step` to `#steps` (read via `attr_reader`); no I/O happens until `PTYRunner#run` actually executes the steps against the live PTY. |

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
9. Raw PTY output is force-encoded to UTF-8 and scrubbed of invalid byte sequences as soon as it's
   read, before any regex runs against it (prompt detection, ANSI stripping, script `wait_for`). A
   wrapped command emitting non-UTF-8 bytes (found via real dogfooding: `swift test`'s output could
   trigger it) does not crash `rune run` with `Encoding::CompatibilityError`.
10. Only rune's own leading `--` separator is stripped from the wrapped command's argv — any
    further `--` tokens the wrapped command uses itself (cargo, npm, git, and others use `--` to
    separate their own flags from pass-through args, e.g. `cargo clippy --tests -- -D warnings`)
    are preserved untouched (found via real external dogfooding).
11. `Script.new { ... }` (and `Script.define { ... }`) evaluate the given block via
    `instance_eval` immediately in the constructor — a block-less `Script.new` (no block given) is
    valid and simply produces an empty `#steps` array, never raising.
12. A timed-out command's spawned OS process is explicitly killed (`SIGKILL`) and reaped, not just
    abandoned — `Timeout.timeout` only interrupts rune's own Ruby control flow, so without this the
    wrapped process kept running as an orphan after `rune run` had already reported exit code 124
    (found via a real `ps aux` check after `rune run --timeout=1 -- sleep 30`).

## Behavioral Examples
- `ruby bin/rune run -- echo "Hello PTY"` outputs clean JSON in agent mode (`--json`) containing `exit_code: 0`, `clean_output: "Hello PTY\n"`, and `duration_ms`.
- `rune run -- nonexistent_binary` returns a *successful* `Result` with `data[:exit_code]: 127`; the `rune` process itself also exits `127`.
- `rune run -- bash -c "exit 7"` — `rune run` (no `--json`) exits `7` at the shell, even though the `Result` is a success.
- `rune run --timeout=5 -- sleep 30` overrides the default 30s timeout and returns exit code 124 after ~5 seconds.
- `rune run --timeout=0 -- echo hi` fails fast with `Result.failure("Invalid --timeout value...")` instead of silently disabling the timeout (Ruby's `Timeout.timeout(0)` means "no timeout", not "instant timeout").
- `rune run --timeout=1 -- sleep 30` returns exit code 124 after ~1 second, and the spawned `sleep`
  process itself is also terminated — it does not keep running in the background afterward.
- `Script.new { wait_for(/\?/); send_keys("y\n") }` passed as `PTYRunner.new(cmd, script:)` waits
  for a `?`-matching prompt in the captured output, then sends `"y\n"` as input, once the wrapped
  command actually runs.

## Error Cases
| Condition | Behavior |
|-----------|----------|
| No command argument | Returns `Result.failure("No command specified...")` |
| Command times out | Returns exit code 124 with timeout message in output |
| `--timeout` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --timeout value...")` before spawning anything |
| `pty` stdlib failed to load | `PTYRunner#run` returns `Result.failure("PTY unavailable: ...")` |
| OS refuses pty allocation at runtime (sandbox/container/exhaustion) | `PTYRunner#run` returns `Result.failure("PTY allocation failed at runtime: ...")` |
| Wrapped command emits bytes that are not valid UTF-8 | Bytes are force-encoded + scrubbed; `Result` still succeeds, no `Encoding::CompatibilityError` |

## Dependencies
- Ruby stdlib: `pty`, `timeout`, `io/wait` (required explicitly — `IO#wait_readable` isn't
  guaranteed to be autoloaded by `pty` alone on every Ruby version)

## Change Log
- v1: Active PTY runner spec contract
- v1: Added `Script` to this module's file/API coverage (previously untracked by spec-sync
  despite being public since `PTYRunner`'s `script:` constructor option shipped); documented the
  explicit `io/wait` require and the timeout-triggered SIGKILL/reap fix for orphaned child
  processes.
