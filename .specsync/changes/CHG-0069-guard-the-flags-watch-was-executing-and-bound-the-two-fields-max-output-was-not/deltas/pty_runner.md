## MODIFIED

### SPEC SECTION Public API

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
| `spawn_and_stream` | internal method | Spawns the PTY and coordinates input, output, signals, and child reaping for the default single-stream mode. |
| `spawn_for_mode` | internal method | Dispatches to `spawn_and_stream` or `spawn_and_stream_separate` depending on `separate_streams`. |
| `spawn_and_stream_separate` | internal method | Spawns stdout on a real pty and stderr on a plain pipe for `separate_streams: true`, reusing the same signal/input/reap machinery as the default mode. |
| `spawn_with_separated_stderr` | internal method | Runs `Process.spawn` with stdout/stdin on the pty slave and stderr on the pipe's write end. |
| `read_separate_streams` | internal method | Multiplexes the stdout pty and stderr pipe with `IO.select`, decoding each independently and appending to its own buffer plus the shared merged `raw_output`. |
| `poll_ready_streams` | internal method | Runs one `IO.select` pass and consumes every stream that became readable. |
| `consume_stream_chunk` | internal method | Reads and decodes one chunk from a single stream, or finalizes it on EOF. |
| `append_decoded_chunk` | internal method | Appends one decoded chunk to a stream's own buffer and the shared `raw_output`. |
| `timeout_hint` | internal method | An extra sentence on a timeout that captured nothing, naming the stdin shape that usually causes it. |
| `prompt_detected_in?` | internal predicate | Checks whether the last non-blank line of a finished text buffer looks like an interactive prompt. |
| `kill_orphaned_child` | internal method | Kills and reaps a timed-out direct child. |
| `wait_for_process` | internal method | Reaps the child and normalizes exit or signal status. |
| `write_input` | internal method | Performs a bounded non-blocking PTY input write. |
| `read_pty_stream` | internal method | Polls the PTY, incrementally decodes output, and drives script steps. |
| `consume_output_chunk` | internal method | Appends one decoded chunk and drives script steps. |
| `process_script_steps` | internal method | Advances ready script steps. |
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
| `apply_output_limit` | internal method | Applies `--max-output` or `--tail` to the merged clean/raw pair. |
| `execute_pty` | internal method | Runs the command in a pty and collects its output. |
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
| `matching_flag` | internal method | Matches one argv token against `FLAG_PATTERNS`, returning the matched option key and `MatchData`, or `[nil, nil]`. |
| `VALUE_FLAGS` | constant | The `run` flags that take a value, derived from `FLAG_PATTERNS` so it cannot drift from the parser. The guard itself moved to `Command.flag_error`, shared with `watch`. |
| `parse_flags` | internal method | Parses every raw `--timeout`/`--max-output`/`--tail` value, stopping at the first invalid one, then checks mutual exclusion. |
| `both_output_limits?` | internal predicate | True when both `--max-output` and `--tail` were given. |
| `parse_positive_int` | internal method | Accepts a positive integer value for `--timeout`/`--max-output`/`--tail` and rejects every other value. |
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
| `drain_available` | internal method | One bounded, best-effort pty read used while tearing an aborted run down; appends to the capture and fires `on_output` without driving script steps. |
| `drain` | internal method | Forwards every signal queued since the last poll, in order, then raises `Aborted` at the burst threshold. |
| `next_signal` | internal method | Pops one queued signal name, or `nil` when the queue is empty. |
| `record_burst` | internal method | Returns the signal's position within the current burst, restarting the count once the burst window has lapsed. |
| `forward` | internal method | Sends one signal to the child, treating an already-dead or permission-denied target as handled. |
| `trap_signal` | internal method | Installs one trap, swallowing an unsupported signal name instead of raising. |
| `restore_signal` | internal method | Restores one signal's previous disposition, defaulting to `DEFAULT`. |
| `interrupted_capture` | internal method | Reaps and builds the capture tuple for a run ended by a repeated signal. |
| `UTF8StreamDecoder` | class | Incrementally decodes chunks while retaining incomplete UTF-8 suffix bytes. |
| `decode` | instance method | Returns complete scrubbed UTF-8 text and buffers an incomplete suffix. |
| `finish` | instance method | Flushes a final incomplete suffix using replacement-character semantics. |
| `sequence_length` | internal method | Maps a valid leading byte to its UTF-8 sequence length. |
| `continuation_bytes?` | internal predicate | Validates UTF-8 continuation bytes. |
| `scrub` | internal method | Force-encodes bytes as UTF-8 and replaces invalid sequences. |


### SPEC SECTION Invariants

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
