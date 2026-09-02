---
module: watch
version: 10
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
| `PTYWatcher` | class | Constructor: `(command, log: $stderr, input: $stdin, output: $stdout, timeout_seconds: nil, idle_timeout_seconds: nil)`. Method: `#watch` returns `Result`. |
| `WatchCommand` | class | Subcommand `rune watch [--log=PATH] [--timeout=SECONDS] [--idle-timeout=SECONDS] <command...>`. It selects live output from the renderer mode and declares usage and flags through the command DSL, so `rune watch --help` renders them without constructing a watcher. |
| `Rune` | module | Top-level rune namespace. |
| `watch` | instance method | Validates terminal support and runs one live watched session. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `call` | instance method | Validates watch arguments, opens the log, selects display output, and runs `PTYWatcher`. |
| `human_render` | instance method | Prints watched-session exit, duration, and log location. |
| `VALUE_FLAGS` | constant | The watch flags that take a value, used by the leftover-flag guard. |
| `TIMEOUT_FLAGS` | constant | Maps each `PTYWatcher` timeout keyword option to its argv pattern, flag name, and error-message value description. |

## Invariants

1. Refuses to run (returns `Result.failure`) unless `input` is a real TTY — live passthrough
   requires an actual terminal to put into raw mode; there is no meaningful non-interactive mode.
2. Refuses to run (returns `Result.failure`) if the `pty` stdlib is unavailable, same check and
   message class as `PTYRunner.pty_available?`.
3. Output is decoded incrementally as UTF-8 before being written or logged, same as `PTYRunner`.
   Incomplete multi-byte suffixes are retained across reads; genuinely invalid bytes are scrubbed.
4. The NDJSON event log emits, in order: one `start` event (`command`, `pid`), zero or more
   `output` events (`bytes`, `text`) as chunks arrive, at most one `timeout` or `idle_timeout` event
   if a bound fired, and exactly one `exit` event (`exit_code`) when the session ends. Every event
   carries a `ts` (float Unix timestamp).
5. `Result#exit_code` (the process-level exit status) mirrors the wrapped command's real exit code
   on a natural exit, same convention as `PTYRunner`/`RunCommand`; on a `--timeout`/`--idle-timeout`
   expiry it is `124`, the same convention `PTYRunner --timeout` already uses.
6. INT/TERM are forwarded to the child using the same `SignalHandler` mechanism as `PTYRunner`,
   including its escalation ladder: every signal is forwarded, and the second one within
   `SignalHandler::BURST_WINDOW_SECONDS` is forwarded and *then* ends the session, reaping the
   child and reporting the conventional `128 + signo` exit code. This matters more here than in
   `PTYRunner` because `rune watch` has no default `--timeout`: before the ladder existed, a child
   that trapped INT/TERM left the session with no bound at all — measured surviving 5x SIGINT +
   5x SIGTERM and needing SIGKILL, a CLI that could not be stopped by an init system. The reap
   happens inside `pump_output`, while the pty reader is still open, because a SIGKILLed pty child
   holding unread output wedges unreapably on macOS and only draining the master clears it (see
   `pty_runner`'s invariant 26); draining also keeps the child's last bytes on screen and in the
   NDJSON log.
   A human's Ctrl-C at the terminal does *not* travel this path. Raw mode clears `ISIG`, so the
   keystroke reaches the child as a `0x03` byte through the input-forwarding thread and the
   child's own pty line discipline, and `rune`'s traps never fire. Verified against a real
   controlling terminal: three Ctrl-Cs, three interrupts delivered to the child, session still
   running. An agent CLI whose first Ctrl-C interrupts a turn is therefore unaffected by the
   ladder, however many times it is pressed.
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
    it does not use a predictable PID/timestamp path or follow a pre-created symlink. A newly
    created explicit `--log=PATH` file is also opened as `0600`.
14. If the display output raises `EPIPE`, the watched child is killed and reaped before the error is
    returned as a structured failure.
15. Array commands are passed to `PTY.spawn` as distinct argv entries. The spawned PID therefore
    belongs to the wrapped target rather than an intermediary shell, so output-sink cleanup,
    signal forwarding, and reaping act on the correct process. The structured `command` field
    remains a shell-escaped display string; explicit string commands retain shell semantics.
    A **single-element** array is the case that needed care: Ruby's `exec` family treats one
    argument as a shell command line, so `rune watch -- 'my file'` reached `sh -c` and split on
    the space, and a name containing `;` or backticks executed. `ExecArgv.for_spawn` passes the
    `[command, argv0]` two-element form for that case, which forces the direct-exec path.
    `PTYWatcher` distinguishes the two by recording whether its constructor received an Array,
    not by counting elements — a watcher built from the `String` form still gets shell semantics
    with one element, which is what its callers expect.
16. `WatchCommand` selects the live passthrough's destination from the output mode and passes it
    explicitly as `PTYWatcher.new(..., output:)`: `$stdout` for a human on a TTY, `$stderr` in agent
    mode (`--json`, `--ndjson`, or non-TTY stdout). Without this the command was the only one that
    never passed `output:` at all, so `PTYWatcher`'s `$stdout` default wrote the child's live bytes
    to the same stream the `Renderer` then wrote the envelope to, and `rune watch --json` produced
    stdout that did not parse as JSON (`unexpected character: 'X' at line 1 column 1`). The live
    view is routed to stderr rather than suppressed because a human is still driving the session
    even when a wrapping process is capturing stdout — the same reasoning that already puts the
    log-path announcement on stderr.
17. `--timeout=SECONDS` bounds total session wall-clock time by wrapping the raw-mode/pump work in
    `Timeout.timeout`. `Timeout.timeout` only interrupts rune's own control flow, so on expiry the
    spawned child is explicitly `SIGKILL`ed and reaped — same reasoning and mechanism as
    `PTYRunner`'s existing `--timeout`. Neither option changes `data`'s shape when unset: no
    `timed_out`/`timeout_kind` key appears when neither `--timeout` nor `--idle-timeout` was given,
    preserving the existing JSON envelope for callers that don't opt in.
18. `--idle-timeout=SECONDS` bounds "no output from the child *and* no input from the human" for
    `SECONDS`, independent of total elapsed time — checked cooperatively inside the existing output
    poll loop (not expressible as a single `Timeout.timeout` deadline, since the window resets on
    any activity). Any decoded output chunk or any chunk read from the human resets the idle clock.
19. `--timeout` and `--idle-timeout` may be combined in the same invocation; whichever bound is
    reached first fires. Both report exit code 124 and `data[:timed_out]: true`, distinguished by
    `data[:timeout_kind]`: `"timeout"` or `"idle_timeout"`.

20. A flag-shaped token before the separator that `watch` does not own is refused, not run.
    Until now anything unrecognised stayed in the argv and became the command: measured through a
    real controlling terminal, `rune watch --timeout 5 -- echo hi` exited **127 with the child never
    running**, because `--timeout` was exec'd as the program. `run` has guarded this since it grew
    flags; `watch` never did, which made it the worse of the two — `run` at least says something.

    The guard is `Command.flag_error`, shared with `run` rather than copied, because the two had
    already drifted once: `run` grew the inline-value branch and `watch` had no guard to grow it in.
    A correctly spelled flag given a space-separated value gets the inline-value message naming
    `rune watch`; anything else gets the unknown-flag message.

    It covers the **leading** position only, which is what `scan_head` leaves behind. A flag `watch`
    owns that appears *after* the program name is still consumed rather than passed to the child —
    `rune watch echo hi --log=/tmp/x` writes rune's own log to the child's path and prints only
    `hi`. That is pre-existing and unchanged here, and it is the asymmetry `session` already closed
    for itself: permuting for consumption and not for validation.

## Behavioral Examples

- `rune watch -- ruby examples/demo_tui.rb` puts your terminal in raw mode, runs the demo TUI
  interactively exactly as if you'd run it directly, prints
  `[rune watch] live event log: /tmp/rune-watch-<unique>.ndjson` once via `warn`, and writes an
  NDJSON event per output chunk to that file — `tail -f` it from another pane to watch live.
  Deliberately *not* stderr by default: stderr shares the human's terminal with the live
  passthrough, interleaving JSON noise into an otherwise-clean interactive session (this was the
  original design and real usage immediately showed it was the wrong default).
- `rune watch --log=/tmp/session.ndjson -- ruby examples/demo_tui.rb` writes the event log to a
  specific file instead of the default temp path, creating a missing file with owner-only `0600`
  permissions.
- `rune watch --log=/dev/stderr -- cmd` (or passing `log: $stderr` directly via the `PTYWatcher`
  Ruby API) still works if stderr is genuinely wanted, e.g. a wrapping process capturing it
  programmatically rather than a human watching the same terminal.
- `rune watch --json -- cmd` writes only `{"status":"ok","data":{...,"log_path":"..."}}` to stdout;
  the child's live output goes to stderr, so `rune watch --json -- cmd 2>/dev/null | jq .data`
  succeeds. `rune watch -- cmd | cat` behaves the same way via non-TTY stdout detection.
- Piping a fake terminal (`#tty? => true`, no `#raw`) and `IO.pipe`s for input/output into
  `PTYWatcher.new` directly drives a real interactive child process end-to-end in a test, without
  a real terminal — see `spec/rune/pty_watcher_spec.rb`.
- `rune watch --timeout=1800 -- some-long-running-agent-tool` returns after at most 30 minutes even
  if the wrapped tool never exits on its own, with `data[:exit_code]: 124` and
  `data[:timeout_kind]: "timeout"` — the case issue #14 exists to cover: an agent invoking `rune
  watch` on a child that hangs forever no longer hangs the agent forever too.
- `rune watch --idle-timeout=120 -- cmd` returns as soon as 2 minutes pass with no output and no
  input, even if the session's total elapsed time is well under any `--timeout` bound — useful when
  "stuck" is a better signal than "ran too long."
- `rune watch --timeout=1800 --idle-timeout=120 -- cmd` combines both; whichever fires first ends
  the session.

## Error Cases

| Condition | Behavior |
|-----------|----------|
| `input` is not a TTY (e.g. piped/non-interactive invocation) | Returns `Result.failure("...requires a real terminal...")` before spawning anything |
| `pty` stdlib unavailable | Returns `Result.failure("PTY unavailable...")` |
| No command argument | Returns `Result.failure("No command specified...")` |
| `--log=` given with no value | Returns `Result.failure("--log requires a path...")` instead of silently smuggling the raw `--log=` token into the wrapped command's argv |
| `--timeout`/`--idle-timeout` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --timeout value..."` or `"Invalid --idle-timeout value..."`)` before spawning anything |
| Wrapped command missing/non-executable | `Result` still succeeds (mirrors `PTYRunner`): `data[:exit_code]` is `127`/`126`, same convention as `rune run`, instead of collapsing to a generic failure |
| Output sink closes with `EPIPE` | Kills and reaps the child, then returns a structured watcher failure |
| `--timeout` elapses | Kills and reaps the child; `Result` succeeds with `data[:exit_code]: 124`, `data[:timed_out]: true`, `data[:timeout_kind]: "timeout"` |
| `--idle-timeout` elapses with no output and no input | Kills and reaps the child; `Result` succeeds with `data[:exit_code]: 124`, `data[:timed_out]: true`, `data[:timeout_kind]: "idle_timeout"` |

## Dependencies

- Ruby stdlib: `pty`, `io/console` (required unconditionally, rescued on `LoadError` the same way
  `pty_runner.rb` rescues `pty` — expected almost everywhere but not guaranteed on every platform),
  `io/wait` (required explicitly for `IO#wait_readable`, same reasoning as `pty_runner.rb`),
  `timeout` (required explicitly for `--timeout`, same as `pty_runner.rb`), `json`, `tempfile`,
  `tmpdir`

## Change Log

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
| 2026-07-29 | CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o: Keep rune watch stdout parseable in agent mode and stop the trust gate passing on an empty commit range |
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-07-29 | CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and: Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible |
| 2026-08-14 | CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t: Add opt-in `--timeout=SECONDS` (total wall-clock) and `--idle-timeout=SECONDS` (no output/input) to `rune watch`, so an agent-driven session can no longer hang forever. Fully additive: the result data shape is unchanged when neither flag is passed. Closes #14. |
| 2026-08-14 | CHG-0021-add-timeout-and-idle-timeout-to-rune-watch-so-an-agent-driven-session-can-t: Add --timeout and --idle-timeout to rune watch so an agent-driven session can't hang forever, closing #14 |
| 2026-08-17 | CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors: Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate |
| 2026-08-17 | CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign: Bound rune run --timeout when the child is still printing, and let a second signal stop rune |
| 2026-08-18 | CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not: Guard the flags watch was executing, and bound the two fields max-output was not |
