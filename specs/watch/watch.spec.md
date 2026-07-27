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
| `PTYWatcher` | class | Constructor: `(command, log: $stderr, input: $stdin, output: $stdout)`. Method: `#watch` returns `Result`. |
| `WatchCommand` | class | Subcommand `rune watch [--log=PATH] <command...>`. `--log=PATH` writes the NDJSON event log to a file instead of stderr; only recognized before a `--` separator, same convention as `RunCommand`'s `--timeout`. |

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
   terminal — a fake terminal object needs only `#tty? => true`; if it doesn't respond to `#raw`,
   the real raw-mode ioctl is skipped entirely.

## Behavioral Examples
- `rune watch -- ruby examples/demo_tui.rb` puts your terminal in raw mode, runs the demo TUI
  interactively exactly as if you'd run it directly, and writes an NDJSON event per output chunk
  to stderr — redirect it to persist/tail the session: `rune watch -- cmd 2>session.ndjson`.
- `rune watch --log=/tmp/session.ndjson -- ruby examples/demo_tui.rb` writes the event log to a
  file instead of stderr.
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
- Ruby stdlib: `pty`, `io/console` (only touched when `input` responds to `#raw`), `json`

## Change Log
- v1: Active spec — initial `rune watch` / `PTYWatcher` contract
