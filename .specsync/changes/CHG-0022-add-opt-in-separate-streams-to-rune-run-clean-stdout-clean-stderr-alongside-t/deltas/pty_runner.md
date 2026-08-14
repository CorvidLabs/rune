## MODIFIED

### SPEC SECTION Public API
| Name | Type | Description |
|------|------|-------------|
| `PTYRunner` | class | Spawns command in PTY. Constructor: `(command, input: nil, script: nil, timeout_seconds: 30, separate_streams: false, &on_output)`. Method: `#run` returns `Result`. Class method: `.pty_available?` reports whether the `pty` stdlib loaded successfully. |
| `RunCommand` | class | Subcommand `rune run [--timeout=SECONDS] [--separate-streams] <command...>` exposing PTY process runner to humans and agents. `--timeout` overrides the default 30s PTYRunner timeout. `--separate-streams` adds `clean_stdout`/`clean_stderr` to the result alongside the existing merged view. Both are only recognized before a `--` separator; a malformed `--timeout` value fails with a clear error instead of leaking the raw flag into the executed command. Declared via the `usage`/`flag` DSL, so `rune run --help` renders them without constructing a PTY runner. |
| `Script` | class | Interactive step DSL passed to `PTYRunner.new(script:)`. Constructor: `Script.new(&block)` (or `Script.define(&block)`, an alias) evaluates the block via `instance_eval`; no I/O happens until `PTYRunner#run` executes the declared steps. |
| `Rune` | module | Top-level rune namespace. |
| `pty_available?` | class predicate | Reports whether Ruby's PTY stdlib loaded successfully. |
| `run` | instance method | Executes, captures, sanitizes, and returns one PTY-backed command result. |
| `detect_prompt?` | instance predicate | Delegates prompt recognition to `PromptDetector`. |
| `spawn_and_stream` | internal method | Spawns the PTY and coordinates input, output, signals, and child reaping for the default single-stream mode. |
| `spawn_for_mode` | internal method | Dispatches to `spawn_and_stream` or `spawn_and_stream_separate` depending on `separate_streams`. |
| `spawn_and_stream_separate` | internal method | Spawns stdout on a real pty and stderr on a plain pipe for `separate_streams: true`, reusing the same signal/input/reap machinery as the default mode. |
| `spawn_with_separated_stderr` | internal method | Runs `Process.spawn` with stdout/stdin on the pty slave and stderr on the pipe's write end. |
| `read_separate_streams` | internal method | Multiplexes the stdout pty and stderr pipe with `IO.select`, decoding each independently and appending to its own buffer plus the shared merged `raw_output`. |
| `poll_ready_streams` | internal method | Runs one `IO.select` pass and consumes every stream that became readable. |
| `consume_stream_chunk` | internal method | Reads and decodes one chunk from a single stream, or finalizes it on EOF. |
| `append_decoded_chunk` | internal method | Appends one decoded chunk to a stream's own buffer and the shared `raw_output`, updating prompt detection. |
| `kill_orphaned_child` | internal method | Kills and reaps a timed-out direct child. |
| `wait_for_process` | internal method | Reaps the child and normalizes exit or signal status. |
| `write_input` | internal method | Performs a bounded non-blocking PTY input write. |
| `read_pty_stream` | internal method | Polls the PTY, incrementally decodes output, and drives script steps. |
| `consume_output_chunk` | internal method | Appends one decoded chunk and updates prompt/script state. |
| `process_script_steps` | internal method | Advances ready script steps. |
| `PTY_LOAD_ERROR` | constant | Captured `LoadError` when PTY support is unavailable. |
| `PTY_ALLOCATION_ERRORS` | constant | OS errors treated as rune-level PTY allocation failures. |
| `command` | reader | Shell-escaped display string. |
| `input` | reader | Optional eager input written after spawn. |
| `script` | reader | Optional interactive `Script`. |
| `timeout_seconds` | reader | Maximum execution duration. |
| `separate_streams` | reader | Whether stdout/stderr are captured on independent streams. |
| `on_output` | reader | Optional decoded-output callback. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `call` | instance method | Validates CLI arguments and delegates to `PTYRunner`. |
| `human_render` | instance method | Prints a concise command summary and captured clean output. |
| `FLAG_PATTERNS` | constant | Maps `--timeout` to its argv pattern, flag name, and error-message value description. |
| `matching_flag` | internal method | Matches one argv token against `FLAG_PATTERNS`, returning the matched option key and `MatchData`, or `[nil, nil]`. |
| `parse_flags` | internal method | Parses the raw `--timeout` value, if any. |
| `parse_positive_int` | internal method | Accepts a positive integer value for `--timeout` and rejects every other value. |
| `wait_for` | DSL method | Appends an output-pattern wait step. |
| `send_keys` | DSL method | Appends a PTY input step. |
| `pause` | DSL method | Appends a timed delay step. |
| `define` | class method | Constructs a `Script` from the DSL block. |
| `Step` | data type | Immutable step record containing `type` and `payload`. |
| `steps` | reader | Ordered script steps. |
| `SignalHandler` | class | Temporarily traps and safely forwards INT/TERM to a child process. |
| `with_traps` | class method | Installs traps for a block and yields a polling forward callable. |
| `UTF8StreamDecoder` | class | Incrementally decodes chunks while retaining incomplete UTF-8 suffix bytes. |
| `decode` | instance method | Returns complete scrubbed UTF-8 text and buffers an incomplete suffix. |
| `finish` | instance method | Flushes a final incomplete suffix using replacement-character semantics. |
| `sequence_length` | internal method | Maps a valid leading byte to its UTF-8 sequence length. |
| `continuation_bytes?` | internal predicate | Validates UTF-8 continuation bytes. |
| `scrub` | internal method | Force-encodes bytes as UTF-8 and replaces invalid sequences. |

### SPEC SECTION Invariants
1. Executed commands run inside a PTY session so TTY-dependent CLIs behave naturally.
2. Output is stripped of ANSI escape sequences before being returned in `clean_output`.
3. Duration of process execution is measured and returned in milliseconds.
4. The command's own exit code is always returned in `data[:exit_code]`, and the `Result` itself
   is `success` (the run was captured) even when the wrapped command's exit code is non-zero.
5. `Result#exit_code` (the process-level exit status `rune run` itself exits with) mirrors the
   wrapped command's exit code, not the `success`/`failure` status of the `Result` — so `rune run
   -- false` composes correctly with shell `&&`/`||`/`set -e` even though the `Result` succeeded.
6. INT/TERM received by the `rune run` process are forwarded to the wrapped child so it terminates
   promptly instead of running to completion; forwarding happens from ordinary code polling between
   reads, never from inside the signal trap itself (see `lib/rune/signal_handler.rb`). This holds in
   both the default single-stream mode and `separate_streams: true`.
7. If the `pty` stdlib failed to load (e.g. unsupported platform), `#run` returns a structured
   failure immediately instead of raising `NameError`/`LoadError`; other rune commands (`version`,
   `help`) remain usable regardless.
8. If the `pty` stdlib loaded but the OS refuses to allocate a pty at runtime (`Errno::ENXIO`,
   `EMFILE`, `ENFILE`, `EPERM` — e.g. a sandbox/container denying it, or pty exhaustion), `#run`
   returns a structured failure instead of raising. This is distinct from `Errno::ENOENT`/`EACCES`
   raised by exec'ing the *target* command, which remain ordinary exit codes (127/126) in
   `data[:exit_code]` on a successful `Result`, since those describe the wrapped command, not rune's
   own environment. Both hold in `separate_streams: true` mode too.
9. Raw PTY output is decoded incrementally as UTF-8 before any regex runs against it (prompt
   detection, ANSI stripping, script `wait_for`). An incomplete multi-byte suffix is retained for
   the next read instead of being corrupted at a chunk boundary; genuinely invalid or final
   incomplete sequences are scrubbed. A wrapped command emitting non-UTF-8 bytes does not crash
   `rune run` with `Encoding::CompatibilityError`. In `separate_streams: true` mode, stdout and
   stderr each get their own independent decoder, so a multi-byte character split across a read
   boundary on one stream is never corrupted by interleaving with the other.
10. Only rune's own leading `--` separator is stripped from the wrapped command's argv — any
    further `--` tokens the wrapped command uses itself (cargo, npm, git, and others use `--` to
    separate their own flags from pass-through args, e.g. `cargo clippy --tests -- -D warnings`)
    are preserved untouched (found via real external dogfooding).
11. `Script.new { ... }` (and `Script.define { ... }`) evaluate the given block via
    `instance_eval` immediately in the constructor — a block-less `Script.new` (no block given) is
    valid and simply produces an empty `#steps` array, never raising.
12. A timed-out command's spawned OS process is explicitly killed (`SIGKILL`) and reaped, not just
    abandoned — `Timeout.timeout` only interrupts rune's own Ruby control flow, so without this the
    wrapped process kept running as an orphan after `rune run` had already reported exit code 124
    (found via a real `ps aux` check after `rune run --timeout=1 -- sleep 30`). Holds identically in
    `separate_streams: true` mode (verified via a real orphan check against that mode too).
13. Array commands are passed to `PTY.spawn` (or, in `separate_streams: true` mode, `Process.spawn`)
    as distinct argv entries instead of being collapsed into a shell command string. This keeps the
    spawned PID attached to the actual target process for signal, timeout, and cleanup handling
    while `command` remains the shell-escaped display value returned in structured results. String
    commands retain their explicit shell semantics.
14. `separate_streams: true` adds `clean_stdout` and `clean_stderr` to `data`, each independently
    ANSI-stripped from that stream alone, alongside the unchanged merged `clean_output`/
    `raw_output` (which still contains both streams' bytes, interleaved in the order each chunk was
    read). When `separate_streams` is not set, `data` has no `clean_stdout`/`clean_stderr` keys at
    all — this preserves the existing JSON envelope for callers that don't opt in.
15. `separate_streams: true` spawns stdout (and stdin, for `input:`) on a real pty as before, but
    stderr on a plain `IO.pipe` instead of sharing the same pty slave — this is what makes
    `clean_stdout`/`clean_stderr` distinguishable at all, since a single pty is one stream by
    construction. The trade-off, and why this is opt-in rather than the default: the child no
    longer has a true controlling-terminal/session-leader relationship (`Process.spawn` redirects
    file descriptors but does not perform the `setsid`/`TIOCSCTTY` a forked `PTY.spawn` child gets
    natively) — irrelevant to rune's own signal forwarding and timeout handling (neither depends on
    terminal-driven job control, see invariant 6 and `SignalHandler`), but a wrapped program relying
    on that relationship itself would behave differently than under the default mode.
16. In `separate_streams: true` mode, the merged `clean_output`/`raw_output` view's cross-stream
    chronological ordering is only as precise as the ~0.2s `IO.select` poll interval — writes to
    stdout and stderr spaced apart by more than that appear in real order, but near-simultaneous
    writes on both streams within the same poll window are not guaranteed byte-exact interleaving.
    This is an inherent property of capturing two independent file descriptors (also true of
    `subprocess.run`'s separate `stdout`/`stderr`, the baseline this feature closes the gap with),
    not something the default single-pty mode has to contend with.
17. `separate_streams: true` combined with `script:` fails immediately with `Result.failure`,
    before spawning anything — the interactive `wait_for`/`send_keys` DSL only has a well-defined
    meaning against one stream. `RunCommand` never sets `script:` from the CLI, so this only
    applies to direct Ruby API callers combining both explicitly.

### SPEC SECTION Behavioral Examples
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
- `rune run --json --separate-streams -- bash -c 'echo out; echo err >&2'` returns
  `clean_stdout: "out\n"` and `clean_stderr: "err\n"` alongside the existing merged
  `clean_output: "out\nerr\n"` — the case issue #15 exists to cover: an agent triaging a failing
  build can now start with "what went to stderr" instead of only seeing one merged stream.
- `rune run --json --separate-streams --timeout=5 -- some_command` combines both flags; a timeout
  still kills and reaps the child, same as the default mode.
- `PTYRunner.new(cmd, separate_streams: true, script: Script.new { ... }).run` returns
  `Result.failure` immediately, before spawning anything.

### SPEC SECTION Error Cases
| Condition | Behavior |
|-----------|----------|
| No command argument | Returns `Result.failure("No command specified...")` |
| Command times out | Returns exit code 124 with timeout message in output |
| `--timeout` value is not a positive integer (`0`, negative, non-numeric, empty) | Returns `Result.failure("Invalid --timeout value...")` before spawning anything |
| `pty` stdlib failed to load | `PTYRunner#run` returns `Result.failure("PTY unavailable: ...")` |
| OS refuses pty allocation at runtime (sandbox/container/exhaustion) | `PTYRunner#run` returns `Result.failure("PTY allocation failed at runtime: ...")` |
| Wrapped command emits bytes that are not valid UTF-8 | Bytes are force-encoded + scrubbed; `Result` still succeeds, no `Encoding::CompatibilityError` |
| A valid UTF-8 character is split across reads | The incomplete suffix is buffered and combined with the following chunk without replacement corruption |
| `separate_streams: true` combined with `script:` | Returns `Result.failure(...)` before spawning anything |

### SPEC SECTION Dependencies
- Ruby stdlib: `pty`, `timeout`, `io/wait` (required explicitly — `IO#wait_readable` isn't
  guaranteed to be autoloaded by `pty` alone on every Ruby version)

### SPEC SECTION Change Log
- v1: Active PTY runner spec contract
- v1: Added `Script` to this module's file/API coverage (previously untracked by spec-sync
  despite being public since `PTYRunner`'s `script:` constructor option shipped); documented the
  explicit `io/wait` require and the timeout-triggered SIGKILL/reap fix for orphaned child
  processes.
- v1: Added boundary-safe incremental UTF-8 decoding shared by `PTYRunner` and `PTYWatcher`.
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-08-14 | CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t: Add opt-in `--separate-streams` to `rune run`: stdout on a real pty, stderr on a plain pipe, adding `clean_stdout`/`clean_stderr` alongside the existing merged `clean_output`/`raw_output` view. Fully additive: the result data shape is unchanged when the flag is not passed. Closes #15. |
