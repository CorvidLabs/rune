---
module: cli
version: 4
status: active
files:
  - lib/rune.rb
  - lib/rune/cli.rb
  - lib/rune/command.rb
  - lib/rune/result.rb
  - lib/rune/renderer.rb
  - lib/rune/version.rb
  - lib/rune/commands/version_command.rb
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
| `Error` | class | Base exception reserved for rune-specific library errors. |
| `Rune` | module | Top-level namespace for the library and CLI framework. |
| `register` | class method | Registers a completed command subclass by its declared command name. |
| `run` | method | Dispatches an argv array, renders its `Result`, and exits with `Result#exit_code`. |
| `commands` | reader | Returns the registered command-name-to-class mapping. |
| `name` | class method | Declares the CLI name for a `Command` subclass. |
| `summary` | class method | Declares the help summary for a `Command` subclass. |
| `inherited` | class hook | Arranges registration when a `Command` subclass definition completes. |
| `call` | instance method | Command execution contract; subclasses must return a `Result`. |
| `human_render` | instance method | Optional command-specific terminal renderer. |
| `command_name` | reader | Returns the subclass's declared CLI name. |
| `command_summary` | reader | Returns the subclass's declared help summary. |
| `success?` | predicate | Reports whether a `Result` has `:ok` status. |
| `failure?` | predicate | Reports whether a `Result` has `:error` status. |
| `success` | class method | Constructs a successful `Result`, optionally with a process exit override. |
| `failure` | class method | Constructs an error `Result`, optionally with data and a process exit override. |
| `to_h` | instance method | Serializes the stable status/data/error envelope. |
| `exit_code` | instance method | Returns the explicit process exit override or the status-derived default. |
| `status` | reader | Returns the symbolic result status. |
| `data` | reader | Returns the result payload, if any. |
| `error` | reader | Returns the result error message, if any. |
| `agent_mode?` | predicate | Selects structured output for explicit JSON modes or non-TTY output. |
| `render` | instance method | Renders one `Result` in NDJSON, JSON, or human form. |
| `render_event` | instance method | Emits and flushes a named NDJSON event when NDJSON mode is active. |
| `io` | reader | Returns the renderer's output stream. |
| `json_mode` | reader | Reports whether explicit JSON rendering is enabled. |
| `ndjson_mode` | reader | Reports whether NDJSON envelope rendering is enabled. |
| `VERSION` | constant | Current rune release version. |
| `VersionCommand` | class | Returns rune, Ruby, platform, and optional-tool version information. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |

## Invariants

1. Commands never print directly to stdout — they return a `Result`
2. `Result#to_h` always includes a `status` key ("ok" or "error")
3. Non-TTY stdout automatically triggers JSON output (agent mode)
4. `--json` flag forces JSON output regardless of TTY
5. `--ndjson` forces a newline-delimited result envelope; live multi-event streaming is provided by
   `rune watch`.
6. `Result#exit_code` defaults to 0 for success / 1 for failure, but a command can override it via
   `exit_code:` on `Result.success`/`.failure` — e.g. `RunCommand`/`WatchCommand` mirror the wrapped
   command's own exit code, so `rune run -- false` composes correctly with shell `&&`/`||`/
   `set -e` even though the `Result` itself is a success. The override affects only the
   process-level exit status, never `Result#to_h`'s serialized JSON shape.
7. Commands self-register via Ruby class inheritance hooks
8. Unknown commands return a structured error, never crash
9. `--json` and `--ndjson` are rune-global only before the first `--` separator. Identical tokens
   after the separator are preserved as wrapped-command arguments.
10. `Rune::VERSION`, `plugin.toml`, and the release tag identify the same semantic version before a
    package can be published. The release ref is an exact Git tag whose commit is reachable from
    `origin/main`.
11. In agent mode, stdout carries the structured envelope and nothing else: the *complete* stdout of
    any command parses as exactly one JSON document (or, under `--ndjson`, one JSON line per
    emitted event). A command that also produces side-effect output while it runs — currently only
    `rune watch`'s live passthrough — must route that output to stderr whenever `--json`/`--ndjson`
    is set or stdout is not a TTY. This is enforced end-to-end against the real `bin/rune`
    executable for every registered command in every agent output mode, asserting over whole
    stdout rather than a substring, because a substring assertion passes against interleaved
    output and previously did.

## Behavioral Examples

- Running `rune version` in a terminal prints human-formatted version info
- Running `rune version --json` reports the current `Rune::VERSION` in the success envelope
- Running `rune version --ndjson` prints `{"event":"result","status":"ok",...}`
- Running `rune run -- tool --json` passes `--json` to `tool` instead of consuming it globally
- Piping `rune version | cat` automatically outputs JSON
- Running `rune nonexistent` returns exit code 1 and an error message
- Running the release-version setter repairs one stale version source when the other already matches
- Running `rune watch --json -- CMD` from a terminal writes only the result envelope to stdout and
  the wrapped command's live output to stderr, so `rune watch --json -- CMD 2>/dev/null | jq`
  succeeds; without the split, stdout began with the child's own bytes and failed to parse

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
- v1: Active spec — CLI framework with dual-mode output and NDJSON envelopes
- v1: Restricted global output-flag extraction to arguments before the first `--`, preserving
  identically named flags for wrapped commands.
| 2026-07-28 | CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery: Adopt and enforce SpecSync 5 for release delivery |
| 2026-07-29 | CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and: Address PR review findings in release synchronization, SDD package coverage, and publish ref validation |
| 2026-07-29 | CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o: Keep rune watch stdout parseable in agent mode and stop the trust gate passing on an empty commit range |
