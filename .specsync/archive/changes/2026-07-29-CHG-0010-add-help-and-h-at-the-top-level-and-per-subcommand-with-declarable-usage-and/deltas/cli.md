## MODIFIED

### SPEC SECTION Public API
| Name | Type | Description |
|------|------|-------------|
| `CLI` | class | CLI router. Class methods: `run(argv)`, `register(command_class)`, `commands`. Instance: `run(argv)`. |
| `Command` | class | Base class for commands. DSL: `name(n)`, `summary(s)`, `usage(text)`, `flag(spec, description)`. Override: `call(args, options)`, `human_render(data, io)`. |
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
| `usage` | class method | Declares the one-line invocation shape shown by `rune <cmd> --help`. |
| `flag` | class method | Declares one command-specific flag (spec + description) for command help. |
| `command_usage` | reader | Returns the subclass's declared usage line, or nil. |
| `command_flags` | reader | Returns the subclass's declared flags, defaulting to an empty array. |
| `Help` | class | Builds and renders `rune --help`, `rune <cmd> --help`, and `rune help [cmd]`. Class method: `.extract_flag!(args)`. Instance: `#overview`, `#for_command(name)`, `#render(data, io)`. |
| `FLAGS` | constant | Tokens (`--help`, `-h`) recognized as a help request before the first `--`. |
| `GLOBAL_FLAGS` | constant | Flags that apply to every command, rendered under "Global flags" and returned in every help payload. |
| `extract_flag!` | class method | Removes every help alias from the pre-separator argv in place and reports whether any were present. |
| `overview` | instance method | Builds the all-commands help `Result`. |
| `for_command` | instance method | Builds one command's help `Result`, or a structured failure for an unknown name. |
| `render_command` | internal method | Renders one command's usage and flag list for a terminal. |
| `render_flags` | internal method | Renders an aligned flag/description list. |

### SPEC SECTION Invariants
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
    is set or stdout is not a TTY.
12. `--help` and `-h` are accepted at the top level and per command, and `rune help <command>` is
    equivalent. Command help never executes the command. Like output flags, help aliases are
    recognized only before the first `--`.
13. Help is a normal `Result`, so agent mode returns the command's `usage` and `flags` as data.
    Every parsed command flag is declared through the command DSL.
14. Help extraction removes every recognized alias before the first separator. Mixed and repeated
    aliases remain help requests and cannot become a command token.
15. Rendering modes are invocation-local. Reusing one `CLI` instance resets help, JSON, and NDJSON
    selection before every dispatch.

### SPEC SECTION Behavioral Examples
- Running `rune version` in a terminal prints human-formatted version info
- Running `rune version --json` reports the current `Rune::VERSION` in the success envelope
- Running `rune version --ndjson` prints a newline-delimited result envelope
- Running `rune run -- tool --json` passes `--json` to `tool`
- Piping `rune version | cat` automatically outputs JSON
- Running `rune nonexistent` returns exit code 1 and an error message
- Running `rune watch --json -- CMD` keeps stdout parseable and routes live output to stderr
- Running `rune --help`, `rune -h`, or `rune help` prints the command overview
- Running `rune run --help` prints declared usage without spawning anything
- Running `rune run --help --json` returns structured usage and flags
- Running `rune run -- mytool --help` passes help to the child
- Running `rune --help -h` returns the overview
- Reusing a `CLI` for help and then version renders version normally

### SPEC SECTION Error Cases
| Condition | Behavior |
|-----------|----------|
| Unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Command raises exception | Caught and wrapped in `Result.failure`, exit code 1 |
| No command given | Shows help output |
| Help requested for an unknown command | Returns `Result.failure` with descriptive error, exit code 1 |

### SPEC SECTION Dependencies
- Ruby stdlib: `json`
- No external runtime dependencies
