---
module: cli
version: 1
status: active
files:
  - lib/rune/cli.rb
  - lib/rune/command.rb
  - lib/rune/result.rb
  - lib/rune/renderer.rb
---
# CLI

## Purpose
Core CLI framework for rune. Provides command registration, argument parsing, dual-mode output (human-pretty for terminals, structured JSON for agents, streaming NDJSON), and the base `Command` class that all commands extend. Designed so that every interaction is first-class for both humans and AI agents.

## Public API
| Name | Type | Description |
|------|------|-------------|
| `CLI` | class | CLI router. Class methods: `run(argv)`, `register(command_class)`, `commands`. Instance: `run(argv)`. |
| `Command` | class | Base class for commands. DSL: `name(n)`, `summary(s)`. Override: `call(args, options)`, `human_render(data, io)`. |
| `Result` | class | Structured result. Class methods: `.success(data, exit_code: nil)`, `.failure(error, data: nil, exit_code: nil)`. Instance: `#success?`, `#failure?`, `#to_h`, `#exit_code`. |
| `Renderer` | class | Output formatter. `#agent_mode?`, `#render(result, human_block:)`. Supports JSON and NDJSON modes. |

## Invariants
1. Commands never print directly to stdout — they return a `Result`
2. `Result#to_h` always includes a `status` key ("ok" or "error")
3. Non-TTY stdout automatically triggers JSON output (agent mode)
4. `--json` flag forces JSON output regardless of TTY
5. `--ndjson` flag forces streaming newline-delimited JSON output
6. `Result#exit_code` defaults to 0 for success / 1 for failure, but a command can override it via
   `exit_code:` on `Result.success`/`.failure` — e.g. `RunCommand`/`WatchCommand` mirror the wrapped
   command's own exit code, so `rune run -- false` composes correctly with shell `&&`/`||`/
   `set -e` even though the `Result` itself is a success. The override affects only the
   process-level exit status, never `Result#to_h`'s serialized JSON shape.
7. Commands self-register via Ruby class inheritance hooks
8. Unknown commands return a structured error, never crash

## Behavioral Examples
- Running `rune version` in a terminal prints human-formatted version info
- Running `rune version --json` prints `{"status":"ok","data":{"version":"0.1.0",...}}`
- Running `rune version --ndjson` prints `{"event":"result","status":"ok",...}`
- Piping `rune version | cat` automatically outputs JSON
- Running `rune nonexistent` returns exit code 1 and an error message

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
- v1: Active spec — CLI framework with dual-mode output and NDJSON streaming
