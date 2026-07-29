## MODIFIED

### SPEC SECTION Public API

| Name | Type | Description |
|------|------|-------------|
| `PTYWatcher` | class | Constructor: `(command, log: $stderr, input: $stdin, output: $stdout)`. Method: `#watch` returns `Result`. The library default is `$stderr`; `WatchCommand` (the CLI) always passes an explicit `File` instead — see below. |
| `WatchCommand` | class | Subcommand `rune watch [--log=PATH] <command...>`. Defaults the NDJSON event log to a temp file (`$stdin.tty?` is checked before anything else, so no file is created if it fails), announcing the path once via `warn`; `--log=PATH` writes it to a specific file instead. Only recognized before a `--` separator, same convention as `RunCommand`'s `--timeout`. Selects the live passthrough's destination from the output mode before spawning the watcher. |
| `Rune` | module | Top-level rune namespace. |
| `watch` | instance method | Validates terminal support and runs one live watched session. |
| `build_result` | internal method | Logs session exit and constructs the duration/exit-code result. |
| `with_raw_input` | internal method | Enters raw terminal mode with a narrow non-TTY fallback. |
| `pump_session` | internal method | Runs output pumping while an input-forwarding thread is active. |
| `forward_input` | internal method | Starts the disposable thread that copies terminal bytes to the child. |
| `pump_output` | internal method | Polls, decodes, displays, logs, and reaps child output. |
| `emit_output` | internal method | Writes and logs one non-empty decoded output chunk. |
| `synchronize_window_size` | internal method | Copies changed terminal dimensions onto the child PTY. |
| `valid_window_size?` | internal predicate | Accepts two positive integer terminal dimensions. |
| `terminate_child` | internal method | Kills and reaps a child after an output-sink failure. |
| `wait_for_exit_code` | internal method | Reaps the child and normalizes exit or signal status. |
| `log_event` | internal method | Writes and flushes one timestamped NDJSON event. |
| `Commands` | module | Namespace containing CLI command implementations. |
| `call` | instance method | Validates watch arguments, opens the log securely, selects the display stream, and runs `PTYWatcher`. |
| `human_render` | instance method | Prints watched-session exit, duration, and log location. |
| `attach_log_path` | internal method | Rebuilds a successful result with the concrete log path. |
| `open_log` | internal method | Opens an explicit append log or creates a private collision-safe temporary log. |
| `extract_log` | internal method | Extracts a non-empty `--log=PATH` before the first separator. |

### SPEC SECTION Invariants

1. Refuses to run (returns `Result.failure`) unless `input` is a real TTY — live passthrough
   requires an actual terminal to put into raw mode; there is no meaningful non-interactive mode.
2. Refuses to run (returns `Result.failure`) if the `pty` stdlib is unavailable, same check and
   message class as `PTYRunner.pty_available?`.
3. Output is decoded incrementally as UTF-8 before being written or logged, same as `PTYRunner`.
   Incomplete multi-byte suffixes are retained across reads; genuinely invalid bytes are scrubbed.
4. The NDJSON event log emits, in order: one `start` event (`command`, `pid`), zero or more
   `output` events (`bytes`, `text`) as chunks arrive, and exactly one `exit` event (`exit_code`)
   when the child exits. Every event carries a `ts` (float Unix timestamp).
5. `Result#exit_code` (the process-level exit status) mirrors the wrapped command's real exit code,
   same convention as `PTYRunner`/`RunCommand`.
6. INT/TERM are forwarded to the child using the same `SignalHandler` mechanism as `PTYRunner`.
7. The input-forwarding thread never blocks process exit: it's explicitly killed once the child's
   output stream ends, regardless of whether it's currently blocked reading more input.
8. `input`/`output`/`log` are constructor-injectable (defaulting to `$stdin`/`$stdout`/`$stderr`),
   specifically so the live-passthrough mechanics are unit-testable without a real controlling
   terminal — a fake terminal object needs only `#tty? => true`; entering raw mode is attempted via
   `input.raw(&block)` and falls back to running the block directly on `Errno::ENOTTY` (not backed
   by a real terminal, e.g. a test's `IO.pipe`) or `NoMethodError` (`#raw` doesn't exist at all).
   `pty_watcher.rb` requires `io/console` itself at load time — a real bug found via live-terminal
   dogfooding was that only a *child* command requiring `io/console` (e.g. `examples/demo_tui.rb`)
   ever gained `#raw`/`#getch`; the parent CLI process's own `$stdin` never did, so raw mode was
   silently never entered for actual `rune watch` usage, leaving the terminal in cooked mode
   (local echo of literal escape sequences, kernel-level line buffering that swallowed
   no-trailing-newline input like arrow keys entirely).
9. `WatchCommand` checks `$stdin.tty?` itself, before doing anything else — including before
   computing/opening the default log file — so a failed invocation (piped/non-interactive) never
   creates a stray temp file. This duplicates `PTYWatcher`'s own internal check by design, at the
   CLI layer specifically to avoid that side effect.
10. `Result#data` on success carries `command`, `exit_code`, and `duration_ms` (milliseconds,
    matching `PTYRunner`'s convention) from `PTYWatcher`. `WatchCommand#call` folds in `log_path`
    (the actual path used, default or `--log=`) before returning, so `human_render` — which runs on
    a separate `Command` instance from the one `#call` ran on, per `CLI#render_result` — can print a
    closing summary and remind where the event log lives without relying on instance state.
11. `WatchCommand#human_render`'s duration is scaled to be readable at the length a watched session
    actually runs (seconds to hours, not `PTYRunner`'s usual sub-second commands): a bare
    `<N>ms` under 1 second, a bare `<N>s` (2 decimal places) under a minute — both already exact
    enough on their own — or `Mm Ss` under an hour / `Hh Mm Ss` beyond that, each followed by
    `, <exact seconds>s` since those coarser forms lose sub-second precision the plain figure
    doesn't need to restate. The exact-seconds suffix is a comma, not parentheses, and only
    appears on the two coarser (minute/hour) forms — not on the sub-minute cases, where it would
    just repeat the same number twice.
12. The controlling terminal's valid row/column size is copied to the child PTY initially and
    whenever it changes during output polling.
13. The default event log is created atomically by `Tempfile` with owner-only `0600` permissions;
    it does not use a predictable PID/timestamp path or follow a pre-created symlink.
14. If the display output raises `EPIPE`, the watched child is killed and reaped before the error is
    returned as a structured failure.
15. Array commands are passed to `PTY.spawn` as distinct argv entries. The spawned PID therefore
    belongs to the wrapped target rather than an intermediary shell, so output-sink cleanup,
    signal forwarding, and reaping act on the correct process. The structured `command` field
    remains a shell-escaped display string; explicit string commands retain shell semantics.
16. `WatchCommand` selects the live passthrough's destination from the output mode and passes it
    explicitly as `PTYWatcher.new(..., output:)`: `$stdout` for a human on a TTY, `$stderr` in agent
    mode (`--json`, `--ndjson`, or non-TTY stdout). Without this the command was the only one that
    never passed `output:` at all, so `PTYWatcher`'s `$stdout` default wrote the child's live bytes
    to the same stream the `Renderer` then wrote the envelope to, and `rune watch --json` produced
    stdout that did not parse as JSON (`unexpected character: 'X' at line 1 column 1`). The live
    view is routed to stderr rather than suppressed because a human is still driving the session
    even when a wrapping process is capturing stdout — the same reasoning that already puts the
    log-path announcement on stderr.

### SPEC SECTION Behavioral Examples

- `rune watch -- ruby examples/demo_tui.rb` puts your terminal in raw mode, runs the demo TUI
  interactively exactly as if you'd run it directly, prints
  `[rune watch] live event log: /tmp/rune-watch-<unique>.ndjson` once via `warn`, and writes an
  NDJSON event per output chunk to that file — `tail -f` it from another pane to watch live.
  Deliberately *not* stderr by default: stderr shares the human's terminal with the live
  passthrough, interleaving JSON noise into an otherwise-clean interactive session (this was the
  original design and real usage immediately showed it was the wrong default).
- `rune watch --log=/tmp/session.ndjson -- ruby examples/demo_tui.rb` writes the event log to a
  specific file instead of the default temp path.
- `rune watch --log=/dev/stderr -- cmd` (or passing `log: $stderr` directly via the `PTYWatcher`
  Ruby API) still works if stderr is genuinely wanted, e.g. a wrapping process capturing it
  programmatically rather than a human watching the same terminal.
- `rune watch --json -- cmd` writes only `{"status":"ok","data":{...,"log_path":"..."}}` to stdout;
  the child's live output goes to stderr, so `rune watch --json -- cmd 2>/dev/null | jq .data`
  succeeds. `rune watch -- cmd | cat` behaves the same way via non-TTY stdout detection.
- Piping a fake terminal (`#tty? => true`, no `#raw`) and `IO.pipe`s for input/output into
  `PTYWatcher.new` directly drives a real interactive child process end-to-end in a test, without
  a real terminal — see `spec/rune/pty_watcher_spec.rb`.

### SPEC SECTION Change Log

- v1: Active spec — initial `rune watch` / `PTYWatcher` contract
- v1: Fixed the root cause of arrow keys/raw input never registering in real `rune watch` usage —
  `pty_watcher.rb` never required `io/console` itself, so the parent process's `$stdin` never
  gained `#raw`. `Result#data` now also carries `duration_ms`/`log_path`, and `WatchCommand`'s
  closing message reports both instead of just the bare exit code.
- v1: Added explicit `require 'io/wait'` (fixing a raw `NoMethodError` crash on Ruby versions
  where it isn't already autoloaded); narrowed `with_raw_input`'s rescue so it only falls back to
  `block.call` for a failure in entering raw mode itself, not for any exception raised from deep
  inside an already-running session (which previously could silently re-run the whole session a
  second time); switched `duration_ms` to a monotonic clock, matching `PTYRunner`; and added the
  missing/non-executable-command exit-code parity and empty-`--log=` error cases above.
- v1: Added incremental UTF-8 decoding, terminal-size synchronization, secure default log creation,
  explicit child cleanup after output `EPIPE`, and direct argv spawning for reliable process
  ownership.
- v1: Routed the live passthrough to stderr in agent mode so `rune watch --json`/`--ndjson`/piped
  stdout emits a parseable structured result instead of the child's raw output followed by the
  envelope. Found by an independent adversarial audit of v0.2.1; the existing unit tests could not
  see it because they replace `PTYWatcher` with a double, so an end-to-end stdout-purity assertion
  over every command in every agent output mode was added alongside the fix.
