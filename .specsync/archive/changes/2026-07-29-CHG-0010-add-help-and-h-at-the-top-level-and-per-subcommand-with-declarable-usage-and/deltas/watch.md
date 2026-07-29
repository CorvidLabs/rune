## MODIFIED

### SPEC SECTION Public API
| Name | Type | Description |
|------|------|-------------|
| `PTYWatcher` | class | Constructor: `(command, log: $stderr, input: $stdin, output: $stdout)`. Method: `#watch` returns `Result`. |
| `WatchCommand` | class | Subcommand `rune watch [--log=PATH] <command...>`. It selects live output from the renderer mode and declares usage and flags through the command DSL, so `rune watch --help` renders them without constructing a watcher. |
| `Rune` | module | Top-level rune namespace. |
| `watch` | instance method | Validates terminal support and runs one live watched session. |
| `build_result` | internal method | Logs session exit and constructs the duration/exit-code result. |
| `with_raw_input` | internal method | Enters raw terminal mode with a narrow non-TTY fallback. |
| `pump_session` | internal method | Runs output pumping while an input-forwarding thread is active. |
| `forward_input` | internal method | Starts the disposable input-forwarding thread. |
| `pump_output` | internal method | Polls, decodes, displays, logs, and reaps child output. |
| `emit_output` | internal method | Writes and logs one non-empty decoded output chunk. |
| `synchronize_window_size` | internal method | Copies changed terminal dimensions onto the child PTY. |
| `valid_window_size?` | internal predicate | Accepts two positive integer terminal dimensions. |
| `terminate_child` | internal method | Kills and reaps a child after an output-sink failure. |
| `wait_for_exit_code` | internal method | Reaps the child and normalizes exit or signal status. |
| `log_event` | internal method | Writes and flushes one timestamped NDJSON event. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `call` | instance method | Validates watch arguments, opens the log, selects display output, and runs `PTYWatcher`. |
| `human_render` | instance method | Prints watched-session exit, duration, and log location. |
| `attach_log_path` | internal method | Adds the concrete log path to a successful result. |
| `open_log` | internal method | Opens an explicit append log or creates a private temporary log. |
| `extract_log` | internal method | Extracts a non-empty `--log=PATH` before the first separator. |
