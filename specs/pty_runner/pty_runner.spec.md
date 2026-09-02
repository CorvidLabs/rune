---
module: pty_runner
version: 12
status: active
files:
  - lib/rune/pty_runner.rb
  - lib/rune/commands/run_command.rb
  - lib/rune/script.rb
  - lib/rune/signal_handler.rb
  - lib/rune/utf8_stream_decoder.rb
  - lib/rune/output_limiter.rb
  - lib/rune/exec_argv.rb
---
# PTY Runner

## Purpose
Pseudo-Terminal (PTY) runner and text sanitizer for `rune`. Spawns un-structured TTY CLI commands in a sandboxed PTY process, cleans ANSI formatting, tracks execution timing, and exposes structured execution contracts to AI agents and humans alike.

## Public API

| Name | Type | Description |
|------|------|-------------|
| `PTYRunner` | class | Spawns command in PTY. Constructor: `(command, input: nil, script: nil, timeout_seconds: 30, max_output_bytes: nil, tail_lines: nil, separate_streams: false, &on_output)`. Method: `#run` returns `Result`. Class method: `.pty_available?` reports whether the `pty` stdlib loaded successfully. |
| `RunCommand` | class | Subcommand `rune run [--timeout=SECONDS] [--max-output=BYTES] [--tail=N] [--separate-streams] <command...>` exposing PTY process runner to humans and agents. `--timeout` overrides the default 30s PTYRunner timeout. `--max-output` bounds `clean_output`/`raw_output` to BYTES each, keeping head+tail. `--tail` keeps only the last N lines of each. `--max-output` and `--tail` are mutually exclusive. `--separate-streams` adds `clean_stdout`/`clean_stderr` to the result alongside the existing merged view. All four are only recognized before a `--` separator; a malformed value fails with a clear error instead of leaking the raw flag into the executed command. Declared via the `usage`/`flag` DSL, so `rune run --help` renders them without constructing a PTY runner. |
| `Script` | class | Interactive step DSL passed to `PTYRunner.new(script:)`. Constructor: `Script.new(&block)` (or `Script.define(&block)`, an alias) evaluates the block via `instance_eval`; no I/O happens until `PTYRunner#run` executes the declared steps. |
| `Rune` | module | Top-level rune namespace. |
| `pty_available?` | class predicate | Reports whether Ruby's PTY stdlib loaded successfully. |
| `ExecArgv` | module | Turns a caller's command into arguments spawn will treat the way the caller meant. |
| `for_spawn` | module function | Forces an argv array to exec directly; leaves a String command line alone. |
| `run` | instance method | Executes, captures, sanitizes, bounds (if requested), and returns one PTY-backed command result. |
| `detect_prompt?` | instance predicate | Delegates prompt recognition to `PromptDetector`. |
| `PTY_LOAD_ERROR` | constant | Captured `LoadError` when PTY support is unavailable. |
| `PTY_ALLOCATION_ERRORS` | constant | OS errors treated as rune-level PTY allocation failures. |
| `command` | reader | Shell-escaped display string. |
| `input` | reader | Optional eager input written after spawn. |
| `script` | reader | Optional interactive `Script`. |
| `timeout_seconds` | reader | Maximum execution duration. |
| `max_output_bytes` | reader | `--max-output` byte budget, or `nil` if unset. |
| `on_output` | reader | Optional decoded-output callback. |
| `OutputLimiter` | class | Bounds captured text without corrupting UTF-8 or splicing a half-escape-sequence at the cut boundary. Stateless; all entry points are class methods. |
| `truncate_middle` | class method | `(text, max_bytes)` returns `[bounded_text, omitted_bytes]`; keeps head and tail with a marker between. `omitted_bytes` is measured in offsets into the original text, which is not the same as "every byte absent from the result" once a cut splits a character. |
| `dangling_suffix` | class method | The trailing bytes of an escape sequence still waiting for its terminator, or empty. |
| `LINE_WITH_TERMINATOR` | constant | One line plus its terminator, where a line ends at CR, LF or CRLF. |
| `elision_marker` | class method | `(omitted)` returns the newline-delimited `[rune] ==== N bytes omitted by --max-output ====` line spliced between head and tail. Not charged against `max_bytes`: it is rune's annotation of the cut, not the child's output. |
| `ELISION_PATTERN` | constant | Matches an elision marker line and captures its byte count, for callers that need to find or verify the join. |
| `DANGLING_ESCAPE` | constant | Matches an escape sequence left without its terminator, anchored at the last ESC before a cut. |
| `COMPLETE_ESCAPE` | constant | Matches the same shapes complete, used to find where the remainder of a split sequence ends inside the tail. |
| `STRING_BODY` | constant | The body of an OSC/DCS control string: any byte but BEL, ESC, CR or LF. Excluding CR and LF is what stops a stray introducer from making a multi-line run of plain text look like one unterminated string. |
| `RESYNC_WINDOW_BYTES` | constant | How far either side of a cut is examined for the sequence that straddles it, and therefore the most either boundary adjustment can remove (512). |
| `tail_lines` | class method | `(text, n)` returns `[bounded_text, omitted_lines]`; keeps only the last `n` lines. Also the name of the matching `PTYRunner` reader holding the `--tail` line budget, or `nil` if unset. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `call` | instance method | Validates CLI arguments and delegates to `PTYRunner`. |
| `human_render` | instance method | Prints a concise command summary and captured clean output. |
| `FLAG_PATTERNS` | constant | Maps each `PTYRunner` value-taking keyword option (`--timeout`, `--max-output`, `--tail`) to its argv pattern, flag name, and error-message value description. `--separate-streams` takes no value, so it is matched separately rather than via this table. |
| `VALUE_FLAGS` | constant | The `run` flags that take a value, derived from `FLAG_PATTERNS` so it cannot drift from the parser. The guard itself moved to `Command.flag_error`, shared with `watch`. |
| `wait_for` | DSL method | Appends an output-pattern wait step. |
| `send_keys` | DSL method | Appends a PTY input step. |
| `pause` | DSL method | Appends a timed delay step. |
| `define` | class method | Constructs a `Script` from the DSL block. |
| `Step` | data type | Immutable step record containing `type` and `payload`. |
| `steps` | reader | Ordered script steps. |
| `SignalHandler` | class | Temporarily traps INT/TERM, forwards every one of them to a child process, and escalates a repeated signal into stopping `rune` itself. |
| `with_traps` | class method | `(pid, burst_window:, abort_after:)` installs traps for a block and yields a polling forward callable. |
| `reap` | class method | `(pid, grace_seconds:, &drain)` gives a signalled child a bounded grace period, then SIGKILLs it, then waits a bounded time for it to become reapable, running `drain` on every poll. Returns its status, or `nil` if it never became reapable inside the bounds. |
| `Aborted` | error class | Raised out of the caller's polling loop once a repeated INT/TERM means `rune` must stop too. |
| `signal_name` | reader | The INT/TERM that triggered the abort. |
| `exit_code` | instance method | The conventional `128 + signo` status for the aborting signal (130 for INT, 143 for TERM). |
| `BURST_WINDOW_SECONDS` | constant | Seconds within which successive signals count as one escalating burst (5.0). |
| `ABORT_AFTER` | constant | Signals within one burst tolerated before `rune` stops itself (2). |
| `ABORT_GRACE_SECONDS` | constant | Grace a just-signalled child gets to leave on its own before SIGKILL (1.0). |
| `POST_KILL_SECONDS` | constant | Bound on waiting for a SIGKILLed child to become reapable (2.0). |
| `POLL_SECONDS` | constant | Reap-loop poll interval (0.02). |
| `UTF8StreamDecoder` | class | Incrementally decodes chunks while retaining incomplete UTF-8 suffix bytes. |
| `decode` | instance method | Returns complete scrubbed UTF-8 text and buffers an incomplete suffix. |
| `finish` | instance method | Flushes a final incomplete suffix using replacement-character semantics. |

## Invariants

22. `data[:prompt_detected]` reflects only the *last* non-blank line of the finished output
    buffer (ANSI stripped), not whether any line anywhere in the run ever matched a prompt
    pattern. `rune run`'s result is only ever read after the wrapped process has already exited or
    been killed by `--timeout`, so this is the question that's actually useful: "was the last
    thing on screen a prompt, with nothing after it" — the signature of a process genuinely stuck
    waiting for input, since by definition nothing else arrives after that line. A prompt-shaped
    line that appears mid-run as ordinary TUI chrome, followed by further real output, does not
    set `prompt_detected` (found via real dogfooding driving a long-running third-party TUI
    sub-agent, where the old "any line ever" semantics made the field `true` on every run and
    therefore useless — issue #30). This holds identically across a natural exit, a
    `PTY::ChildExited` short-circuit, and a `--timeout` kill: the last-line check runs against
    whatever `raw_output` was captured up to the point execution stopped, in every case.
23. No output at all, or output consisting only of blank/whitespace lines, yields
    `data[:prompt_detected]: false` — never a crash from an absent "last line".
24. No trapped signal is ever swallowed. Every INT/TERM caught while a child is running is
    forwarded to that child, in arrival order, for as long as the run lasts. The forward callable
    used to latch after its first successful forward, so signals two onward reached neither the
    child nor `rune` itself: measured as a `rune run` absorbing 4x SIGINT + 2x SIGTERM over three
    seconds and leaving only when its own `--timeout` fired 15s later, and as a `rune watch`
    (which has no default timeout) surviving 5x SIGINT + 5x SIGTERM and needing SIGKILL. Signals
    are queued rather than held in a single slot, so two arriving inside one 0.2s poll interval
    are both delivered instead of overwriting each other.
25. The second INT/TERM within `SignalHandler::BURST_WINDOW_SECONDS` ends the run, the same
    escalation `timeout`, `docker run`, and `ssh` use: it is forwarded to the child *first* — a
    child whose second Ctrl-C interrupts a turn still receives it — and only then is
    `SignalHandler::Aborted` raised out of the polling loop. `rune` unwinds to a well-formed
    result rather than dying mid-render: the child is reaped, the capture keeps everything it
    printed on the way out, `[rune] Interrupted by SIG<NAME>` is appended, and the reported exit
    code is the conventional `128 + signo` (130 for INT, 143 for TERM). A single signal is still
    the child's alone — it is forwarded and `rune` keeps waiting, so the traps continue to do what
    they were installed for instead of `rune` dying instantly and orphaning the child. Signals
    further apart than the burst window are independent first signals, so a long-lived session
    legitimately interrupted once now and once ten minutes later is not torn down by the second.
    Once `rune` has aborted, INT/TERM are restored to their default dispositions, so a third
    signal during teardown kills `rune` outright — deliberately, as the last escape hatch.
26. Every wait on a signalled child is bounded, and the child's pty is drained while it dies.
    Both are load-bearing on macOS rather than defensive: a pty child SIGKILLed while bytes it
    wrote are still sitting unread in the pty buffer wedges *permanently* in the kernel's exit
    path (`ps` reports `?Es`), and from there it is never reapable again — a blocking
    `Process.wait2` never returns, `WNOHANG` polling never succeeds, and waiting minutes does not
    help; only reading the pty master clears it. This is the ordinary shape of an abort, because
    the last thing a child does on its way out is usually to print something, and it hung the real
    CLI for over three minutes on a 20-second `--timeout` before the drain existed. The abort path
    therefore reaps from inside the read loop, where the reader is still open. `--timeout`'s kill
    path is bounded for the same reason but cannot drain — Ruby's internal timeout exception is
    not a `StandardError`, so it cannot be caught while the reader is still in scope — so it gives
    up on a wedged child rather than blocking forever.

27. `--max-output` bounds `clean_output` and `raw_output` **independently, each to the same
    budget**. That is the stated contract — the flag says "BYTES each" — and it is what a caller
    sizing a context window wants, since both fields land under the cap. The consequence is not
    stated anywhere and surprised a reporter: because a pty turns every `\n` into `\r\n` and
    `raw_output` also keeps its escapes, the same budget lands at different points in the child's
    output, so under this flag **`clean_output` is not `strip_ansi(raw_output)`**, and `raw_output`
    carries its own marker with a different count. Measured on a 5,200-byte ASCII fixture at
    `--max-output=200`: metadata `omitted_bytes: 5000`, raw's own marker `5070`, and with colour a
    whole line of the child's output was present in one field and absent from the other.

    `omitted_bytes` is `clean_output`'s count. Deriving `clean_output` from the bounded raw instead —
    which is what `session read` does, and correctly for its own contract — was rejected here: it
    would cut the readable payload by the ANSI fraction on every colour-emitting child, against the
    flag's stated purpose. A separate additive `raw_omitted_bytes` is a plausible future change.

28. `omitted_bytes` reconciles exactly with the source on ASCII and does not on multi-byte
    text. It is measured in offsets into the original, so when a cut splits a character the orphaned
    fragment is in neither the result nor the count, and `scrub` may replace it with a longer
    U+FFFD. Measured drift: 0-6 bytes on Hangul, up to 7 on 4-byte emoji, and 2-byte Latin-1 at 121
    of 245 budgets — not a CJK curiosity. A caller cannot verify how much was dropped by arithmetic
    on non-ASCII input. Making it reconcile would mean discarding the split character's fragment,
    which contradicts the scrub invariant, and redefining it would change the marker's rendered
    length and could flip `truncated` for callers who changed nothing.

29. `--max-output` and `--tail` bound `clean_stdout` and `clean_stderr` as well as the merged
    fields. They were not bounded at all: a 200-byte budget returned 10,506 bytes across the four
    fields, because only `clean_output` and `raw_output` went through `apply_output_limit`. A caller
    sets the flag to cap what comes back, and adding `--separate-streams` — which surfaces the same
    output twice more — should not silently uncap it. Measured after: 1,012 bytes for the same
    budget. Each field is bounded to the same budget, which is the "BYTES each" contract already
    stated, and their omitted counts are not surfaced for the same reason `raw_output`'s is not:
    one reply carries one count and it is `clean_output`'s. With neither flag set the fields are
    byte-for-byte unchanged.

## Behavioral Examples

- `ruby bin/rune run -- echo "Hello PTY"` outputs clean JSON in agent mode (`--json`) containing `exit_code: 0`, `clean_output: "Hello PTY\n"`, and `duration_ms`.
- `rune run -- nonexistent_binary` returns a *successful* `Result` with `data[:exit_code]: 127`; the `rune` process itself also exits `127`.
- `rune run -- bash -c "exit 7"` — `rune run` (no `--json`) exits `7` at the shell, even though the `Result` is a success.
- `rune run --timeout=5 -- sleep 30` overrides the default 30s timeout and returns exit code 124 after ~5 seconds.
- `rune run --timeout=0 -- echo hi` fails fast with `Result.failure("Invalid --timeout value...")` instead of silently disabling the timeout (Ruby's `Timeout.timeout(0)` means "no timeout", not "instant timeout").
- `rune run --timeout=1 -- sleep 30` returns exit code 124 after ~1 second, and the spawned `sleep`
  process itself is also terminated — it does not keep running in the background afterward.
- `Script.new { wait_for(/\?/); send_keys("y\n") }` passed as `PTYRunner.new(cmd, script:)` waits
  for a `?`-matching prompt in the captured output, then sends `"y\n"` as input, once the wrapped
  command actually runs.
- `rune run --json --timeout=5 --max-output=65536 -- yes` returns a `clean_output`/`raw_output`
  bounded to 65536 bytes each (head+tail) instead of the multi-megabyte unbounded payload the same
  command produces without the flag, with `truncated: true` and the exact `omitted_bytes` count.
- The head and tail are joined by a `[rune] ==== N bytes omitted by --max-output ====` line rather
  than spliced. Without it the returned text is a fabrication: a 201-byte transcript at
  `--max-output=200` dropped exactly the byte that turned `chsh -s /bin/zsh` into
  `chsh -s bin/zsh`, a different and still-plausible path, under `status: ok`. The marker is not
  charged against `BYTES`, so a result may exceed the budget by its length — the budget bounds the
  child's output, and `scrub` has overshot it the same way since the flag shipped, whenever both
  cuts split a multi-byte character.
- Neither cut boundary lands inside an escape sequence. Censused over all 14,029 cut points of a
  real vim transcript, 2,306 head cuts and 4,399 tail cuts fell inside one, and every one of them
  emitted the orphaned remainder; after the boundary adjustment none do. A head that kept an OSC
  introducer without its terminator makes `strip_ansi` swallow the marker and the start of the
  tail; a tail that begins mid-CSI prints its remainder as text (`\e[1;31m` cut after `\e[` shows
  `31m`, confirmed on both GNU screen and pyte).
- `rune run --tiemout=5 -- echo hi` is rejected with `Unknown option: --tiemout` rather than
  exec'd, which used to give `status: ok` with `exit_code: 127`. Only tokens before the first
  operand are examined, so `rune run cargo clippy --tests` and `rune run -- mytool --tiemout=5`
  both pass their own flags through untouched.
- `rune run --json --tail=20 -- some_verbose_build` returns only the last 20 lines of
  `clean_output`/`raw_output`, with `truncated: true` and `omitted_lines` set to however many lines
  were dropped.
- `rune run --json --separate-streams -- bash -c 'echo out; echo err >&2'` returns
  `clean_stdout: "out\n"` and `clean_stderr: "err\n"` alongside the existing merged
  `clean_output: "out\nerr\n"` — the case issue #15 exists to cover: an agent triaging a failing
  build can now start with "what went to stderr" instead of only seeing one merged stream.
- `rune run --json --separate-streams --timeout=5 -- some_command` combines both flags; a timeout
  still kills and reaps the child, same as the default mode.
- `PTYRunner.new(cmd, separate_streams: true, script: Script.new { ... }).run` returns
  `Result.failure` immediately, before spawning anything.
- `ruby -e 'puts "user@host:~$ "; puts "still working"; puts "done"'` run via `rune run` reports
  `prompt_detected: false` — the prompt-shaped first line is not the last line.
- `ruby -e 'puts "Password: "'` run via `rune run` reports `prompt_detected: true` — the prompt is
  the last (and only) line.
- `rune run --timeout=1 -- ruby -e 'puts "Password: "; sleep 5'` reports `exit_code: 124` and
  `prompt_detected: true` — the timeout-killed run's last on-screen line was a genuine prompt.
- `rune run --json --timeout=20 -- <child that traps INT and prints from the handler>` sent two
  SIGINTs half a second apart exits `130` about 1.6s after the first one, with the child reaped
  and *both* of the child's INT replies present in `clean_output` — the second one is drained out
  of the pty during teardown rather than lost with it. The same run given a single SIGINT forwards
  it and keeps waiting, reaching `124` at the `--timeout` as before.
- `rune run --json --timeout=20 -- <same child>` sent the originally measured 4x SIGINT + 2x
  SIGTERM burst exits `130` on the second signal instead of running to the timeout.
- `rune run --json --timeout=20 -- <same child>` sent two SIGTERMs exits `143`.
- `rune watch -- <child that traps INT/TERM>`, with no `--timeout` at all, exits `130` on the
  second signal; before this it survived 5x SIGINT + 5x SIGTERM and had to be SIGKILLed.
- A human's Ctrl-C under `rune watch` never reaches these traps: raw mode clears `ISIG`, so the
  keystroke travels to the child as a `0x03` byte through the input-forwarding thread and the
  child's own pty line discipline. Verified against a real controlling terminal — three Ctrl-Cs,
  three interrupts delivered to the child, session still running — so an agent CLI whose first
  Ctrl-C interrupts a turn is unaffected however many times it is pressed.

## Error Cases

| Condition | Behavior |
|-----------|----------|
| No command argument | Returns `Result.failure("No command specified...")` |
| Command times out | Returns exit code 124 with timeout message in output |
| `--timeout` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --timeout value...")` before spawning anything |
| `--max-output` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --max-output value...")` before spawning anything |
| `--tail` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --tail value...")` before spawning anything |
| Both `--max-output` and `--tail` are given | Returns `Result.failure("Cannot combine --max-output and --tail...")` before spawning anything |
| `pty` stdlib failed to load | `PTYRunner#run` returns `Result.failure("PTY unavailable: ...")` |
| OS refuses pty allocation at runtime (sandbox/container/exhaustion) | `PTYRunner#run` returns `Result.failure("PTY allocation failed at runtime: ...")` |
| Wrapped command emits bytes that are not valid UTF-8 | Bytes are force-encoded + scrubbed; `Result` still succeeds, no `Encoding::CompatibilityError` |
| A valid UTF-8 character is split across reads | The incomplete suffix is buffered and combined with the following chunk without replacement corruption |
| A `--max-output` cut lands inside a multi-byte UTF-8 character | The truncated head/tail is scrubbed rather than raising or leaving an invalid byte sequence |
| A `--max-output` cut lands inside an escape sequence | The head is pulled back to the sequence's ESC and the tail forward past its final byte; both adjustments are counted in `omitted_bytes` and bounded by `RESYNC_WINDOW_BYTES` |
| A `--max-output` cut lands inside a sequence longer than `RESYNC_WINDOW_BYTES` | The boundary is left where it was — the pre-existing behaviour — rather than a guess being made |
| A rune flag is mistyped before the wrapped command (`--tiemout=5`) | Returns `Result.failure("Unknown option: --tiemout...")` before spawning anything |
| `separate_streams: true` combined with `script:` | Returns `Result.failure(...)` before spawning anything |
| A second INT/TERM arrives within the burst window | The signal is forwarded to the child, then the run ends: the child is reaped (bounded grace, then SIGKILL), `[rune] Interrupted by SIG<NAME>` is appended to the capture, and a successful `Result` reports `exit_code` `128 + signo` |
| A signalled pty child wedges unreapably in the kernel exit path | The abort path drains the pty master, which clears the wedge; every wait is bounded regardless, so `rune` still exits |

## Dependencies

- Ruby stdlib: `pty`, `timeout`, `io/wait` (required explicitly — `IO#wait_readable` isn't
  guaranteed to be autoloaded by `pty` alone on every Ruby version)

## Change Log

- v1: Active PTY runner spec contract
- v1: Added `Script` to this module's file/API coverage (previously untracked by spec-sync
  despite being public since `PTYRunner`'s `script:` constructor option shipped); documented the
  explicit `io/wait` require and the timeout-triggered SIGKILL/reap fix for orphaned child
  processes.
- v1: Added boundary-safe incremental UTF-8 decoding shared by `PTYRunner` and `PTYWatcher`.
- v6: `SignalHandler` forwards every INT/TERM instead of latching after the first, escalates a
  repeated signal into stopping `rune` itself at `128 + signo`, and reaps signalled children with
  bounded, pty-draining waits.
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-08-14 | CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a: Add opt-in `--max-output=BYTES` (head+tail truncation) and `--tail=N` to `rune run`, plus the new `OutputLimiter` module. Fully additive: the result data shape is unchanged when neither flag is passed. Closes #12. |
| 2026-08-14 | CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a: Add opt-in bounded output to rune run: --max-output=BYTES head+tail truncation and --tail=N, closing #12 |
| 2026-08-14 | CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t: Add opt-in `--separate-streams` to `rune run`: stdout on a real pty, stderr on a plain pipe, adding `clean_stdout`/`clean_stderr` alongside the existing merged `clean_output`/`raw_output` view. Fully additive: the result data shape is unchanged when the flag is not passed. Closes #15. |
| 2026-08-14 | CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t: Add opt-in --separate-streams to rune run: clean_stdout/clean_stderr alongside the merged view, closing #15 |
| 2026-08-14 | CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e: Fix `prompt_detected` to reflect only the last non-blank line of output instead of any line seen across the whole run; also fixes a latent bug where `--timeout` kills always reported `prompt_detected: false` regardless of actual content. Closes #30. |
| 2026-08-14 | CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e: Fix prompt_detected to reflect the last non-blank line of output, not any line ever seen, closing #30 |
| 2026-08-17 | CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors: Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate |
| 2026-08-17 | CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign: Bound rune run --timeout when the child is still printing, and let a second signal stop rune |
| 2026-08-18 | CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the: Stop a read mid-escape: withhold an unterminated sequence from the text and the cursor |
| 2026-08-18 | CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg: Make --tail count a carriage return as a line break, and report matched on a regex send's timeout |
| 2026-08-18 | CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun: Correct the flag message run gets wrong, and the five contracts the dogfood found documented wrong |
| 2026-08-18 | CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not: Guard the flags watch was executing, and bound the two fields max-output was not |
