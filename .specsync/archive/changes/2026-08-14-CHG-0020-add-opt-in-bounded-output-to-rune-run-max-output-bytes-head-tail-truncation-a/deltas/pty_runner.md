## MODIFIED

### SPEC SECTION Public API
| Name | Type | Description |
|------|------|-------------|
| `PTYRunner` | class | Spawns command in PTY. Constructor: `(command, input: nil, script: nil, timeout_seconds: 30, max_output_bytes: nil, tail_lines: nil, &on_output)`. Method: `#run` returns `Result`. Class method: `.pty_available?` reports whether the `pty` stdlib loaded successfully. |
| `RunCommand` | class | Subcommand `rune run [--timeout=SECONDS] [--max-output=BYTES] [--tail=N] <command...>` exposing PTY process runner to humans and agents. `--timeout` overrides the default 30s PTYRunner timeout. `--max-output` bounds `clean_output`/`raw_output` to BYTES each, keeping head+tail. `--tail` keeps only the last N lines of each. `--max-output` and `--tail` are mutually exclusive. All three are only recognized before a `--` separator; a malformed value fails with a clear error instead of leaking the raw flag into the executed command. Declared via the `usage`/`flag` DSL, so `rune run --help` renders them without constructing a PTY runner. |
| `Script` | class | Interactive step DSL passed to `PTYRunner.new(script:)`. Constructor: `Script.new(&block)` (or `Script.define(&block)`, an alias) evaluates the block via `instance_eval`; no I/O happens until `PTYRunner#run` executes the declared steps. |
| `Rune` | module | Top-level rune namespace. |
| `pty_available?` | class predicate | Reports whether Ruby's PTY stdlib loaded successfully. |
| `run` | instance method | Executes, captures, sanitizes, bounds (if requested), and returns one PTY-backed command result. |
| `detect_prompt?` | instance predicate | Delegates prompt recognition to `PromptDetector`. |
| `spawn_and_stream` | internal method | Spawns the PTY and coordinates input, output, signals, and child reaping. |
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
| `max_output_bytes` | reader | `--max-output` byte budget, or `nil` if unset. |
| `on_output` | reader | Optional decoded-output callback. |
| `OutputLimiter` | class | Bounds captured text without corrupting UTF-8 at the cut boundary. Stateless; both methods are class methods. |
| `truncate_middle` | class method | `(text, max_bytes)` returns `[bounded_text, omitted_bytes]`; keeps head and tail, omits the middle, byte-exact. |
| `tail_lines` | class method | `(text, n)` returns `[bounded_text, omitted_lines]`; keeps only the last `n` lines. Also the name of the matching `PTYRunner` reader holding the `--tail` line budget, or `nil` if unset. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `call` | instance method | Validates CLI arguments and delegates to `PTYRunner`. |
| `human_render` | instance method | Prints a concise command summary and captured clean output. |
| `parse_positive_int` | internal method | Accepts a positive integer value for `--timeout`/`--max-output`/`--tail` and rejects every other value. |
| `matching_flag` | internal method | Matches one argv token against `FLAG_PATTERNS`, returning the matched option key and `MatchData`, or `[nil, nil]`. |
| `parse_flags` | internal method | Parses every raw `--timeout`/`--max-output`/`--tail` value, stopping at the first invalid one, then checks mutual exclusion. |
| `both_output_limits?` | internal predicate | True when both `--max-output` and `--tail` were given. |
| `FLAG_PATTERNS` | constant | Maps each `PTYRunner` keyword option to its argv pattern, flag name, and error-message value description. |
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
   reads, never from inside the signal trap itself (see `lib/rune/signal_handler.rb`).
7. If the `pty` stdlib failed to load (e.g. unsupported platform), `#run` returns a structured
   failure immediately instead of raising `NameError`/`LoadError`; other rune commands (`version`,
   `help`) remain usable regardless.
8. If the `pty` stdlib loaded but the OS refuses to allocate a pty at runtime (`Errno::ENXIO`,
   `EMFILE`, `ENFILE`, `EPERM` — e.g. a sandbox/container denying it, or pty exhaustion), `#run`
   returns a structured failure instead of raising. This is distinct from `Errno::ENOENT`/`EACCES`
   raised by exec'ing the *target* command, which remain ordinary exit codes (127/126) in
   `data[:exit_code]` on a successful `Result`, since those describe the wrapped command, not rune's
   own environment.
9. Raw PTY output is decoded incrementally as UTF-8 before any regex runs against it (prompt
   detection, ANSI stripping, script `wait_for`). An incomplete multi-byte suffix is retained for
   the next read instead of being corrupted at a chunk boundary; genuinely invalid or final
   incomplete sequences are scrubbed. A wrapped command emitting non-UTF-8 bytes does not crash
   `rune run` with `Encoding::CompatibilityError`.
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
    (found via a real `ps aux` check after `rune run --timeout=1 -- sleep 30`).
13. Array commands are passed to `PTY.spawn` as distinct argv entries instead of being collapsed
    into a shell command string. This keeps the spawned PID attached to the actual target process
    for signal, timeout, and cleanup handling while `command` remains the shell-escaped display
    value returned in structured results. String commands retain their explicit shell semantics.
14. Neither `--max-output` nor `--tail` changes `data`'s shape when unset: no `truncated`,
    `omitted_bytes`, or `omitted_lines` key appears, and `clean_output`/`raw_output` are exactly
    what they would be without the flags. This preserves the existing JSON envelope for callers
    that don't opt in.
15. `--max-output=BYTES` bounds `clean_output` and `raw_output` independently, each to at most
    `BYTES` bytes, keeping the head and tail and omitting the middle; `data[:truncated]` and
    `data[:omitted_bytes]` are always present when the flag is given, even when nothing needed
    omitting (`omitted_bytes: 0`, `truncated: false`). `omitted_bytes` reflects `clean_output`'s
    own omitted count specifically — `raw_output` is bounded to the same byte budget
    independently, but since it still contains ANSI codes and cursor movements its own omitted
    count is not necessarily identical and is not separately surfaced. The cut never splits a
    multi-byte UTF-8 character into an invalid sequence.
16. `--tail=N` keeps only the last `N` lines of `clean_output` and `raw_output` independently;
    `data[:truncated]` and `data[:omitted_lines]` are always present when the flag is given, and
    (as with `--max-output`) `omitted_lines` reflects `clean_output`'s own count.
17. `--max-output` and `--tail` are mutually exclusive; passing both fails before spawning
    anything.

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
- `rune run --json --timeout=5 --max-output=65536 -- yes` returns a `clean_output`/`raw_output`
  bounded to 65536 bytes each (head+tail) instead of the multi-megabyte unbounded payload the same
  command produces without the flag, with `truncated: true` and the exact `omitted_bytes` count.
- `rune run --json --tail=20 -- some_verbose_build` returns only the last 20 lines of
  `clean_output`/`raw_output`, with `truncated: true` and `omitted_lines` set to however many lines
  were dropped.

### SPEC SECTION Error Cases
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

### SPEC SECTION Change Log
- v1: Active PTY runner spec contract
- v1: Added `Script` to this module's file/API coverage (previously untracked by spec-sync
  despite being public since `PTYRunner`'s `script:` constructor option shipped); documented the
  explicit `io/wait` require and the timeout-triggered SIGKILL/reap fix for orphaned child
  processes.
- v1: Added boundary-safe incremental UTF-8 decoding shared by `PTYRunner` and `PTYWatcher`.
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-08-14 | CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a: Add opt-in `--max-output=BYTES` (head+tail truncation) and `--tail=N` to `rune run`, plus the new `OutputLimiter` module. Fully additive: the result data shape is unchanged when neither flag is passed. Closes #12. |
