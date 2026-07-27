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
| `PTYRunner` | class | Spawns command in PTY. Constructor: `(command, input: nil, script: nil, timeout_seconds: 30, &on_output)`. Method: `#run` returns `Result`. |
| `RunCommand` | class | Subcommand `rune run [--timeout=SECONDS] <command...>` exposing PTY process runner to humans and agents. `--timeout` overrides the default 30s PTYRunner timeout; only recognized before a `--` separator. |

## Invariants
1. Executed commands run inside a PTY session so TTY-dependent CLIs behave naturally.
2. Output is stripped of ANSI escape sequences before being returned in `clean_output`.
3. Duration of process execution is measured and returned in milliseconds.
4. Missing commands return a structured failure result with exit code 1.

## Behavioral Examples
- `ruby bin/rune run -- echo "Hello PTY"` outputs clean JSON in agent mode (`--json`) containing `exit_code: 0`, `clean_output: "Hello PTY\n"`, and `duration_ms`.
- `rune run -- nonexistent_binary` returns structured failure.
- `rune run --timeout=5 -- sleep 30` overrides the default 30s timeout and returns exit code 124 after ~5 seconds.

## Error Cases
| Condition | Behavior |
|-----------|----------|
| No command argument | Returns `Result.failure("No command specified...")` |
| Command times out | Returns exit code 124 with timeout message in output |

## Dependencies
- Ruby stdlib: `pty`, `timeout`

## Change Log
- v1: Active PTY runner spec contract
