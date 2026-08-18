## MODIFIED

### SPEC SECTION Public API

| Name | Type | Description |
|------|------|-------------|
| `CLI` | class | CLI router. Class methods: `run(argv)`, `register(command_class)`, `commands`. Instance: `run(argv)`. |
| `Command` | class | Base class for commands. DSL: `name(n)`, `summary(s)`, `usage(text)`, `flag(spec, description)`. Override: `call(args, options)`, `human_render(data, io)`. Shared: `flag_shaped?(token)`. |
| `FLAG_SHAPED` | constant | Matches a token shaped like one of rune's own long flags — `--`, a letter, flag characters, optional `=value`. Deliberately narrow: the same argv position also carries input text and wrapped-command argv, so `---`, `--- section ---` and any token with a space are not flags. |
| `flag_shaped?` | class method | Whether a token looks like a long flag rune could have meant to own. Commands use it to tell a mistyped flag from their own operands, so an unrecognized `--flag` is refused rather than exec'd or typed at a child. |
| `Result` | class | Structured result. Class methods: `.success(data, exit_code: nil)`, `.failure(error, data: nil, exit_code: nil)`. Instance: `#success?`, `#failure?`, `#to_h`, `#exit_code`. |
| `Renderer` | class | Output formatter. `#agent_mode?`, `#render(result, human_block:)`. Supports JSON and NDJSON modes. |
| `Error` | class | Base exception reserved for rune-specific library errors. |
| `Rune` | module | Top-level namespace for the library and CLI framework. |
| `register` | class method | Registers a command subclass immediately after its DSL name is declared. |
| `run` | method | Dispatches an argv array, renders its `Result`, and exits with `Result#exit_code`. |
| `commands` | reader | Returns the registered command-name-to-class mapping. |
| `name` | class method | With an argument, declares and registers the CLI name for a `Command` subclass; without one, returns the normal Ruby class name. |
| `summary` | class method | Declares the help summary for a `Command` subclass. |
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
| `subcommand` | class method | Declares one subcommand (name + summary) for command help. |
| `command_subcommands` | reader | Returns the subclass's declared subcommands, defaulting to an empty array. |
| `flag_error` | class method | Rejects a flag-shaped token that reached the wrapped command's argv, shared by `run` and `watch`. |
| `INLINE_VALUE_ERROR` | constant | Message template for a flag the command owns whose value was space-separated. |
| `UNKNOWN_FLAG_ERROR` | constant | Message template for a flag-shaped token the command does not own. |
| `Help` | class | Builds and renders `rune --help`, `rune <cmd> --help`, and `rune help [cmd]`. Class method: `.extract_flag!(args)`. Instance: `#overview`, `#for_command(name)`, `#render(data, io)`. |
| `FLAGS` | constant | Tokens (`--help`, `-h`) recognized as a help request before the first `--`. |
| `GLOBAL_FLAGS` | constant | Flags that apply to every command, rendered under "Global flags" and returned in every help payload. |
| `extract_flag!` | class method | Removes every help alias from the pre-separator argv in place and reports whether any were present. |
| `overview` | instance method | Builds the all-commands help `Result`. |
| `for_command` | instance method | Builds one command's help `Result`, or a structured failure for an unknown name. |
| `render_command` | internal method | Renders one command's usage and flag list for a terminal. |
| `render_flags` | internal method | Renders an aligned flag/description list. |

