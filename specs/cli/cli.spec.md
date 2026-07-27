---
module: cli
version: 1
status: draft
files:
  - lib/xzst/cli.rb
  - lib/xzst/command.rb
  - lib/xzst/result.rb
  - lib/xzst/renderer.rb
---
# CLI

## Purpose
Core CLI framework for xzst. Provides command registration, argument parsing, dual-mode output (human-pretty for terminals, structured JSON for agents), and the base `Command` class that all commands extend. Designed so that every interaction is first-class for both humans and AI agents.

## Public API
| Name | Type | Description |
|------|------|-------------|
| `CLI` | class | CLI router. Class methods: `run(argv)`, `register(command_class)`, `commands`. Instance: `run(argv)`. |
| `Command` | class | Base class for commands. DSL: `name(n)`, `summary(s)`. Override: `call(args, options)`, `human_render(data, io)`. |
| `Result` | class | Structured result. Class methods: `.success(data)`, `.failure(error)`. Instance: `#success?`, `#failure?`, `#to_h`, `#exit_code`. |
| `Renderer` | class | Output formatter. `#agent_mode?`, `#render(result, human_block:)`. Auto-detects TTY vs pipe. |

## Invariants
1. Commands never print directly to stdout — they return a `Result`
2. `Result#to_h` always includes a `status` key ("ok" or "error")
3. Non-TTY stdout automatically triggers JSON output (agent mode)
4. `--json` flag forces JSON output regardless of TTY
5. Exit code 0 for success, 1 for errors, 2 for usage errors
6. Commands self-register via Ruby class inheritance hooks
7. Unknown commands return a structured error, never crash

## Behavioral Examples
- Running `xzst version` in a terminal prints human-formatted version info
- Running `xzst version --json` prints `{"status":"ok","data":{"version":"0.1.0",...}}`
- Piping `xzst version | cat` automatically outputs JSON
- Running `xzst nonexistent` returns exit code 1 and an error message
- Running `xzst help` lists all registered commands

## Error Cases
| Condition | Behavior |
|-----------|----------|
| Unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Command raises exception | Caught and wrapped in `Result.failure`, exit code 1 |
| No command given | Shows help output |

## Dependencies
- Ruby stdlib: `optparse`, `json`
- No external runtime dependencies

## Change Log
- v1: Initial spec — CLI framework with dual-mode output
