## MODIFIED

### SPEC SECTION Invariants

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

