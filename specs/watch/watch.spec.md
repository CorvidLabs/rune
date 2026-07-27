---
module: watch
version: 1
status: active
files:
  - lib/rune/pty_watcher.rb
  - lib/rune/commands/watch_command.rb
---
# PTY Watcher (`rune watch`)

## Purpose
Live, bidirectional interactive passthrough for a command in a PTY. Unlike `PTYRunner` (which
buffers a command's entire output and only returns it once the command finishes), `PTYWatcher`
forwards a human's keystrokes to the child as they're typed and streams the child's output to the
screen as it arrives, while simultaneously logging every chunk as an NDJSON event so an agent can
tail the session live. Deliberately a separate class from `PTYRunner`, not a mode bolted onto it:
`PTYRunner`'s "run, capture, return once" contract is frozen for 0.2.0, and the execution model
here (raw terminal mode, a background input-forwarding thread) is different enough not to belong
there.

## Public API
| Name | Type | Description |
|------|------|-------------|
| `PTYWatcher` | class | Constructor: `(command, log: $stderr, input: $stdin, output: $stdout)`. Method: `#watch` returns `Result`. The library default is `$stderr`; `WatchCommand` (the CLI) always passes an explicit `File` instead — see below. |
| `WatchCommand` | class | Subcommand `rune watch [--log=PATH] <command...>`. Defaults the NDJSON event log to a temp file (`$stdin.tty?` is checked before anything else, so no file is created if it fails), announcing the path once via `warn`; `--log=PATH` writes it to a specific file instead. Only recognized before a `--` separator, same convention as `RunCommand`'s `--timeout`. |

## Invariants
1. Refuses to run (returns `Result.failure`) unless `input` is a real TTY — live passthrough
   requires an actual terminal to put into raw mode; there is no meaningful non-interactive mode.
2. Refuses to run (returns `Result.failure`) if the `pty` stdlib is unavailable, same check and
   message class as `PTYRunner.pty_available?`.
3. Every output chunk is force-encoded to UTF-8 and scrubbed of invalid byte sequences before being
   written or logged, same as `PTYRunner` — a wrapped command emitting non-UTF-8 bytes does not
   crash the session.
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

## Behavioral Examples
- `rune watch -- ruby examples/demo_tui.rb` puts your terminal in raw mode, runs the demo TUI
  interactively exactly as if you'd run it directly, prints
  `[rune watch] live event log: /tmp/rune-watch-<pid>-<ts>.ndjson` once via `warn`, and writes an
  NDJSON event per output chunk to that file — `tail -f` it from another pane to watch live.
  Deliberately *not* stderr by default: stderr shares the human's terminal with the live
  passthrough, interleaving JSON noise into an otherwise-clean interactive session (this was the
  original design and real usage immediately showed it was the wrong default).
- `rune watch --log=/tmp/session.ndjson -- ruby examples/demo_tui.rb` writes the event log to a
  specific file instead of the default temp path.
- `rune watch --log=/dev/stderr -- cmd` (or passing `log: $stderr` directly via the `PTYWatcher`
  Ruby API) still works if stderr is genuinely wanted, e.g. a wrapping process capturing it
  programmatically rather than a human watching the same terminal.
- Piping a fake terminal (`#tty? => true`, no `#raw`) and `IO.pipe`s for input/output into
  `PTYWatcher.new` directly drives a real interactive child process end-to-end in a test, without
  a real terminal — see `spec/rune/pty_watcher_spec.rb`.

## Error Cases
| Condition | Behavior |
|-----------|----------|
| `input` is not a TTY (e.g. piped/non-interactive invocation) | Returns `Result.failure("...requires a real terminal...")` before spawning anything |
| `pty` stdlib unavailable | Returns `Result.failure("PTY unavailable...")` |
| No command argument | Returns `Result.failure("No command specified...")` |

## Dependencies
- Ruby stdlib: `pty`, `io/console` (required unconditionally, rescued on `LoadError` the same way
  `pty_runner.rb` rescues `pty` — expected almost everywhere but not guaranteed on every platform),
  `json`

## Change Log
- v1: Active spec — initial `rune watch` / `PTYWatcher` contract
- v1: Fixed the root cause of arrow keys/raw input never registering in real `rune watch` usage —
  `pty_watcher.rb` never required `io/console` itself, so the parent process's `$stdin` never
  gained `#raw`. `Result#data` now also carries `duration_ms`/`log_path`, and `WatchCommand`'s
  closing message reports both instead of just the bare exit code.
