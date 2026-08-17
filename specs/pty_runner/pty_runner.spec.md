---
module: pty_runner
version: 6
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
| `truncate_middle` | class method | `(text, max_bytes)` returns `[bounded_text, omitted_bytes]`; keeps `max_bytes` of the original as a head and a tail, omits the middle, and joins them with `elision_marker`. Both cut boundaries are pulled to an escape-sequence boundary first: the head back to the ESC of a sequence it split, the tail forward past the final byte of one. `omitted_bytes` counts every original byte not in the result, marker excluded. |
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
| `unknown_flag_error` | internal method | Rejects a flag-shaped token that appears before the first operand and matches no rune flag, instead of letting it be exec'd as the program name. Examines nothing after the first operand, so a wrapped command's own long flags pass through. |
| `parse_flags` | internal method | Parses every raw `--timeout`/`--max-output`/`--tail` value, stopping at the first invalid one, then checks mutual exclusion. |
| `both_output_limits?` | internal predicate | True when both `--max-output` and `--tail` were given. |
| `parse_positive_int` | internal method | Accepts a positive integer value for `--timeout`/`--max-output`/`--tail` and rejects every other value. |
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
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-08-14 | CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a: Add opt-in `--max-output=BYTES` (head+tail truncation) and `--tail=N` to `rune run`, plus the new `OutputLimiter` module. Fully additive: the result data shape is unchanged when neither flag is passed. Closes #12. |
| 2026-08-14 | CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a: Add opt-in bounded output to rune run: --max-output=BYTES head+tail truncation and --tail=N, closing #12 |
| 2026-08-14 | CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t: Add opt-in `--separate-streams` to `rune run`: stdout on a real pty, stderr on a plain pipe, adding `clean_stdout`/`clean_stderr` alongside the existing merged `clean_output`/`raw_output` view. Fully additive: the result data shape is unchanged when the flag is not passed. Closes #15. |
| 2026-08-14 | CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t: Add opt-in --separate-streams to rune run: clean_stdout/clean_stderr alongside the merged view, closing #15 |
| 2026-08-14 | CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e: Fix `prompt_detected` to reflect only the last non-blank line of output instead of any line seen across the whole run; also fixes a latent bug where `--timeout` kills always reported `prompt_detected: false` regardless of actual content. Closes #30. |
| 2026-08-14 | CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e: Fix prompt_detected to reflect the last non-blank line of output, not any line ever seen, closing #30 |
| 2026-08-17 | CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors: Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate |
