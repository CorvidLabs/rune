## MODIFIED

### SPEC SECTION Public API

| Name | Type | Description |
|------|------|-------------|
| `Session` | module | Namespace for persistent session support. |
| `Rune` | module | Top-level rune namespace. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `Store` | class | Per-session state on disk: `RUNE_HOME` resolution, owner-only dirs/files, `meta.json` read/write, liveness. |
| `Supervisor` | class | The detached process owning one session's PTY master and serving its control socket. |
| `Client` | class | One request/reply exchange against a session's control socket. |
| `Unavailable` | class | Raised when a control socket is missing or refuses a connection — how a dead supervisor presents. |
| `PromptScanner` | module | Reports whether the last non-blank line of text looks like an interactive prompt. |
| `SessionCommand` | class | Subcommand `rune session <start\|send\|read\|attach\|list\|stop\|archive>`. |
| `home` | reader | Returns the resolved session-state root for this store. |
| `default_home` | class method | Resolves `RUNE_HOME`, treating an empty value as unset, else `~/.rune`. |
| `valid_name?` | class predicate | Accepts only session names safe to use as a directory component. |
| `alive?` | class predicate | Asks the OS whether a pid exists; `EPERM` counts as alive, a bad value as dead. |
| `with_bindable_path` | class method | Runs a bind/connect against a path short enough for `sockaddr_un`, chdir-ing into the session directory when the absolute path is too long. |
| `sessions_dir` | instance method | Returns the directory holding every session. |
| `session_dir` | instance method | Returns one session's directory. |
| `meta_path` | instance method | Returns one session's `meta.json` path. |
| `output_path` | instance method | Returns one session's NDJSON transcript path. |
| `socket_path` | instance method | Returns one session's control-socket path. |
| `exist?` | instance predicate | Reports whether a session directory exists. |
| `names` | instance method | Lists known session names in sorted order. |
| `create` | instance method | Creates a session directory and forces owner-only permissions. |
| `remove` | instance method | Deletes a session directory and its contents. |
| `write_meta` | instance method | Writes `meta.json` with owner-only permissions. |
| `read_meta` | instance method | Reads `meta.json`, returning nil when absent or unparseable. |
| `update_meta` | instance method | Merges fields into existing metadata, or nil when the session is unknown. |
| `open_output` | instance method | Opens the append-only transcript for the supervisor's lifetime, owner-only and unbuffered. |
| `DEFAULT_DIR_NAME` | constant | Directory name used under the home directory when `RUNE_HOME` is unset. |
| `DIR_MODE` | constant | Owner-only directory mode for session state. |
| `FILE_MODE` | constant | Owner-only file mode for session state. |
| `NAME_PATTERN` | constant | Pattern a session name must match to be usable as a directory component. |
| `SOCKET_PATH_LIMIT` | constant | Path length beyond which socket bind/connect switches to a session-relative path. |
| `run` | instance method | Runs one supervised session: detach, bind the socket, spawn the child, serve until it ends. |
| `pump` | internal method | Reads and decodes one chunk from the pty, marking the child finished at EOF. |
| `append` | internal method | Appends decoded output to the transcript, records activity, and logs an event. |
| `handle_request` | internal method | Reads one JSON request line from a client and dispatches it. |
| `dispatch` | internal method | Routes one control request to its handler. |
| `handle_send` | internal method | Writes input to the child and either replies immediately or begins a pending settle. |
| `write_to_child` | internal method | Writes the request text to the pty and schedules the terminating carriage return as a separate write. |
| `schedule_submit` | internal method | Records when the terminating carriage return becomes due. |
| `deliver_submit` | internal method | Writes the terminator once its delay has passed and the text has drained. |
| `flush_submit` | internal method | Writes any outstanding terminator immediately, preserving order against a new send. |
| `SUBMIT_DELAY` | constant | How long after a send's text the terminating carriage return is written. |
| `begin_pending` | internal method | Records the send cursor, settle window, regex, deadline, and echo for an in-flight send. |
| `resolve_pending` | internal method | Re-evaluates an in-flight send against new output once per loop tick. |
| `pending_outcome` | internal method | Selects the outcome for an in-flight send, or nil to keep waiting. |
| `beyond_echo` | internal method | Returns the portion of a response past the pty's echo of the input, handling a partially-arrived echo. |
| `quiet_enough?` | internal predicate | True once non-echo output has arrived and the child has been quiet for the settle window. |
| `settle_pending` | internal method | Replies to an in-flight send and clears the pending state. |
| `handle_stop` | internal method | Acknowledges a stop request and ends the event loop. |
| `status_payload` | internal method | Builds the reply for a `status` request. |
| `respond` | internal method | Writes one JSON reply line and closes the client. |
| `accept_client` | internal method | Accepts a waiting control connection without blocking. |
| `finish` | internal method | Records the session's exit code and logs the closing event. |
| `reap` | internal method | Reaps the child and normalizes exit or signal status. |
| `cleanup` | internal method | Tears down pending clients, the child, the socket, and the transcript handle. |
| `resolve_orphaned_pending` | internal method | Replies to a send that would otherwise never be answered because the supervisor is exiting. |
| `terminate_child` | internal method | Kills and reaps a still-running child. |
| `safe_close` | internal method | Closes an IO, tolerating one already closed. |
| `log_event` | internal method | Appends one timestamped NDJSON event to the transcript. |
| `compile_regex` | internal method | Compiles `--wait-for-regex` with a bounded match budget, returning nil when absent or invalid. |
| `regex_matched?` | internal predicate | True on a match, false on none, nil when the pattern exceeded its match budget. |
| `supports_regex_timeout?` | internal predicate | Whether this Ruby can bound a single regex match. |
| `REGEX_MATCH_TIMEOUT` | constant | How long one `--wait-for-regex` match may run before the pattern is abandoned. |
| `REGEX_TIMEOUT_ERROR` | constant | The regex-timeout error class, or an unraised stand-in on Ruby without one. |
| `positive_int` | internal method | Coerces a request value to a positive integer, falling back to a default. |
| `monotonic` | internal method | Returns the monotonic clock reading used for settle and deadline arithmetic. |
| `CHILD_ENV` | constant | Environment forced on the child, neutralizing interactive pagers. |
| `POLL_INTERVAL` | constant | Event-loop tick used to poll the pty and re-evaluate a pending send. |
| `READ_CHUNK` | constant | Maximum bytes read from the pty per iteration. |
| `DEFAULT_ROWS` | constant | Rows given to the child's pty, since a detached session has no terminal to copy. |
| `DEFAULT_COLUMNS` | constant | Columns given to the child's pty, since a detached session has no terminal to copy. |
| `request` | instance method | Sends one JSON request and returns the parsed reply. |
| `available?` | instance predicate | Reports whether the control socket currently accepts a connection. |
| `prompt_at_end?` | module function | True when the last non-blank line of text looks like an interactive prompt. |
| `call` | instance method | Routes a `rune session` subcommand, including the hidden supervisor entry point. |
| `human_render` | instance method | Renders sessions, transcript output, or a structured summary for a terminal. |
| `supervise` | internal method | Hidden entry point that runs the detached supervisor for one session. |
| `await_ready` | internal method | Waits for the supervisor to report ready, treating an already-exited child as ready. |
| `abandon` | internal method | Tears down a supervisor that was spawned but never became usable. |
| `executable_path` | internal method | Resolves rune's own executable, used to re-invoke it as the supervisor. |
| `send_input` | internal method | Validates send arguments and performs the control exchange. |
| `send_payload` | internal method | Builds the control-socket payload for a send. |
| `validate_regex` | internal method | Rejects an invalid `--wait-for-regex` before anything is sent. |
| `exchange` | internal method | Performs one control-socket request against a live session, mapping failures to results. |
| `alive_session` | internal method | Returns a failure result unless the named session's supervisor is alive. |
| `read_transcript` | internal method | Serves transcript output with cursor, tail, and byte bounds. |
| `transcript_for` | internal method | Replays the NDJSON transcript from disk into the concatenated output text. |
| `slice_from` | internal method | Returns transcript bytes at or after a cursor. |
| `bound_output` | internal method | Applies `--tail`/`--max-output` and reports what was omitted. |
| `list` | internal method | Describes every known session. |
| `describe` | internal method | Builds one session's row, recomputing state from real process liveness. |
| `stop` | internal method | Stops a session gracefully, then force-kills any survivor, idempotently. |
| `graceful_stop` | internal method | Asks the supervisor to stop over its control socket, tolerating an unreachable one. |
| `kill_remaining` | internal method | Force-kills any surviving child and supervisor, tolerating already-dead pids. |
| `extract_options` | internal method | Extracts session flags before the first `--`, leaving the wrapped command untouched. |
| `consume_flag` | internal method | Consumes one boolean or value flag at an argv position. |
| `consume_value_flag` | internal method | Consumes a value flag in either `--flag=value` or `--flag value` form. |
| `assign` | internal method | Coerces and stores one flag value, reporting a message on failure. |
| `separate_form?` | internal predicate | Matches the space-separated spelling of a value flag. |
| `dashed` | internal method | Renders an option key as its user-facing flag name. |
| `flag_alias` | internal method | Maps internal option keys whose flag names differ to those names. |
| `coerce` | internal method | Coerces a raw flag value according to its declared kind. |
| `integer` | internal method | Parses an integer flag value, enforcing positivity where required. |
| `name_error` | internal method | Builds the message for a missing or invalid session name. |
| `no_such_session` | internal method | Builds the message for an unknown session name. |
| `render_list` | internal method | Renders the session list for a terminal. |
| `store` | internal method | Returns the memoized store for this invocation. |
| `SUBCOMMANDS` | constant | User-facing session subcommands, used for help and error messages. |
| `START_TIMEOUT` | constant | How long `start` waits for the supervisor to report ready. |
| `VALUE_FLAGS` | constant | Maps each option key to its argv pattern and value kind. |
| `BOOLEAN_FLAGS` | constant | Maps valueless flags to their option keys. |
| `reset_transcript` | instance method | Clears a session's transcript so a reused name starts a lifetime whose offsets match its new supervisor. |
| `broadcast` | internal method | Writes one output chunk to every attached terminal, dropping any that has gone away. |
| `handle_attach` | internal method | Acknowledges an attach, replays the current screen, and promotes the client to a raw duplex pipe. |
| `recent_transcript` | internal method | The trailing slice of transcript replayed to an attaching terminal. |
| `forward_from_attached` | internal method | Forwards bytes typed on an attached terminal into the child's pty. |
| `within_echo_grace?` | internal predicate | True while a prefix of the input may still be the pty's own echo rather than a reply. |
| `ECHO_GRACE_SECONDS` | constant | How long after a send a prefix-of-input is still assumed to be the pty echo. |
| `ATTACH_BACKLOG_BYTES` | constant | How much existing transcript an attaching terminal is replayed. |
| `Attachment` | class | Connects a human terminal to a live session until the detach key is pressed. |
| `close_quietly` | internal method | Closes the control socket and prints the closing note, tolerating an already-closed socket. |
| `forward_keystrokes` | internal method | Sends typed bytes to the session, stopping at the detach key but still delivering what preceded it. |
| `render_output` | internal method | Writes one chunk of session output to the local terminal. |
| `DETACH_KEY` | constant | Ctrl-], the key that detaches and leaves the session running. |
| `DETACH_HINT` | constant | The detach instruction shown when a terminal attaches. |
| `CHUNK` | constant | Maximum bytes moved per read while attached. |
| `with_clean_output` | internal method | Adds the ANSI-stripped `clean_output` beside a reply's raw output, matching `rune run`. |
| `attach` | internal method | Validates the session and hands a real terminal to it. |
| `GRACEFUL_STOP_TIMEOUT` | constant | How long `stop` waits for a cooperative shutdown before force-killing. |
| `DISPATCH` | constant | Maps each session subcommand, including the hidden supervisor entry point, to its handler. |
| `project` | reader | Returns the project slug this store is scoped to. |
| `project_slug` | class method | Builds a readable, collision-safe identifier for a project directory. |
| `project_root` | class method | The enclosing git working tree, or the directory itself outside one. |
| `canonical` | class method | Resolves a path through symlinks so one directory cannot get two project identities. |
| `projects` | class method | Lists every project that has session state under a home. |
| `project_dir` | instance method | Returns this project's directory under the home. |
| `archive_dir` | instance method | Returns this project's archive directory. |
| `archive` | instance method | Moves a stopped session into the dated archive, freeing its name. |
| `archived_names` | instance method | Lists archived session directories for this project. |
| `generate_name` | instance method | Picks an unused `<tool>-<word>` codename for a command. |
| `CODENAMES` | constant | Word list paired with a tool name to form generated session names. |
| `archive_session` | internal method | Archives a stopped session after validating it. |
| `archive_rejection` | internal method | Returns the failure that blocks an archive, or nil to proceed. |
| `still_running` | internal method | Message explaining that a session must be stopped before archiving. |
| `list_archived` | internal method | Lists this project's archived sessions. |
| `list_all_projects` | internal method | Lists live sessions across every project, labelled by project. |
| `activity` | internal method | Reports idle time and the last meaningful line from a session's transcript tail. |
| `tail_events` | internal method | Parses the trailing NDJSON events of a transcript without reading the whole file. |
| `summarize` | internal method | Reduces an output chunk to one readable, escape-free line. |
| `idle_suffix` | internal method | Renders idle time for the terminal session list. |
| `await_death` | internal method | Waits for signalled pids to disappear so `stop` is complete when it returns. |
| `ACTIVITY_TAIL_BYTES` | constant | How much of a transcript's tail `list` reads for activity reporting. |
| `ACTIVITY_LINE_LIMIT` | constant | Maximum length of the reported last line. |
| `DEATH_TIMEOUT` | constant | How long `stop` waits for signalled processes to actually exit. |
| `pending_client` | internal method | The in-flight send's socket, watched so a caller that goes away is noticed. |
| `discard_disconnected_pending` | internal method | Releases an in-flight send whose caller has closed its socket. |
| `client_gone?` | internal predicate | True when a readable client socket is at EOF rather than carrying data. |
| `read_request_line` | internal method | Reads one control request within a bound, so a partial line cannot freeze the loop. |
| `echo_still_arriving?` | internal predicate | True when the trailing bytes received are the start of the echo still in flight. |
| `kill_group` | internal method | Signals the child's process group, falling back to the single pid. |
| `REQUEST_READ_TIMEOUT` | constant | How long one control request may take to deliver a complete line. |
| `MAX_REQUEST_BYTES` | constant | Largest control request accepted before the client is dropped. |
| `readiness` | internal method | Reports :ready, an error, or nil to keep waiting during start. |
| `serving?` | internal predicate | True when a session records running, has a socket, and its supervisor is alive. |
| `supervisor_died` | internal method | Message pointing at supervisor.log when the supervisor exited during start. |
| `client_ceiling` | internal method | Caller-side bound on a send, so a wedged supervisor cannot hang the caller. |
| `kill_process_group` | internal method | Force-kills a child and its workers by process group. |
| `kill_pid` | internal method | Force-kills a single pid, tolerating one already gone. |
| `DEFAULT_SEND_TIMEOUT_MS` | constant | Mirrors the supervisor's send timeout so the caller's ceiling is never tighter. |
| `CLIENT_TIMEOUT_MARGIN` | constant | Slack added to the caller's ceiling so it never pre-empts a legitimate wait. |
| `lock_path` | instance method | Returns the per-session start lock path. |
| `with_start_lock` | instance method | Serialises `start` for one session name under an exclusive lock. |
| `enqueue` | internal method | Queues bytes for an IO and attempts an immediate non-blocking flush. |
| `drain_outbox` | internal method | Flushes queued bytes to every IO the event loop reported writable. |
| `flush_outbox` | internal method | Writes as much of one IO's queue as it will take without blocking. |
| `drop_writer` | internal method | Handles an IO that failed to accept a write, distinguishing the pty from a terminal. |
| `detach` | internal method | Removes an attached terminal and restores the headless size when it was the last. |
| `reap_idle_clients` | internal method | Closes control connections that connected and never sent a request. |
| `handle_resize` | internal method | Applies a resize request sent over its own control connection. |
| `resize_child` | internal method | Sets the child's pty dimensions and signals SIGWINCH so it re-lays-out. |
| `MAX_OUTBOX_BYTES` | constant | Ceiling on undrained output for one attached terminal before it is dropped. |
| `DEFAULT_SETTLE_MS` | constant | How long the child must be quiet before a send is considered answered. |
| `EXIT_SUPERVISOR_CRASHED` | constant | Exit code recorded when the supervisor itself died rather than the child. |
| `crashed` | internal method | Records why the supervisor died and finishes the session. |
| `child_still_talking?` | internal predicate | True when the child produced output within the settle window at send time. |
| `serialized_launch` | internal method | Runs the conflict check and launch for one name under the start lock. |
| `screen_field` | internal method | Renders the transcript for `read --screen`, or nothing when not asked. |
| `screen_after` | internal method | Renders the settled screen for `send --screen`, client-side. |
| `read_payload` | internal method | Builds the result body for a transcript read. |
| `GENERATED_NAME_ATTEMPTS` | constant | How many codenames a start without `--name` tries before giving up. |
| `REPLY_DRAIN_TIMEOUT` | constant | How long teardown keeps pushing out replies that are already queued. |
| `drain_replies` | internal method | Delivers queued replies before teardown closes their sockets. |
| `start_rejection` | internal method | Returns the failure that blocks a start, or nil to proceed. |
| `running_conflict` | internal method | Returns a failure when the name already has a live supervisor. |
| `launch` | internal method | Creates session state, spawns the supervisor, and waits for readiness. |
| `spawn_supervisor` | internal method | Re-invokes rune's executable as the detached supervisor for one session. |

> Note: `conclude`, `handshake`, `with_raw_terminal`, `connect`, `name_base`, `socket_live?`,
> `terminal_size`, `forward_resize`, `forward_pending_resize` and `with_resize_forwarding` are
> intentionally absent from the table above. They exist and are exercised by the suite, but
> SpecSync's Ruby extractor does not surface them from their position in the class body
> (rune#20 / spec-sync#479), and documenting an export it cannot see fails the contract check.
> The membership of this list is not stable: it moves whenever a neighbouring declaration is added
> or removed, which is the position-dependency the upstream issue describes — `serialized_launch`
> became visible purely because the method that followed it was deleted.
> This matches the existing convention in `pty_runner`'s spec for the same upstream bug.


### SPEC SECTION Known Limitations

- **A single line of 1024 bytes or more is silently discarded by a cooked-mode child's terminal.**
  This is `MAX_CANON`, a tty limit rather than a rune bound: the line discipline cannot assemble a
  longer canonical line, so it drops it and the child never sees it. Measured exactly — 1023 bytes
  arrive, 1024 do not, with no error anywhere. Raw-mode children (which is most full-screen agent
  CLIs) are unaffected: 300KB arrives byte-perfect. This matters because an agent prompt easily
  exceeds 1KB and nothing reports the loss. Send such input to a cooked-mode child in chunks, or
  drive a raw-mode target.
- **On Ruby 3.0 and 3.1 a `--wait-for-regex` pattern can still wedge a session.** Per-`Regexp`
  timeouts arrived in 3.2; below that there is no way to bound a single match, so a catastrophically
  backtracking pattern blocks the supervisor's only thread with no recovery but `stop`. Ruby 3.2 and
  later also memoize most textbook cases, but that optimization is disabled for patterns using
  backreferences, which is why the bound matters even there.
- **`stop` signals the pids recorded in `meta.json`.** If a supervisor was SIGKILLed and the kernel
  has since recycled its pid, `stop` could signal an unrelated process. Narrow, but real.
- **Settle is a heuristic, but it is a better one than 0.4.0 claimed.** That release recorded the
  reply being the answer to the question actually asked in only 5/9 turns at 800 ms, and raised the
  default to 3000 on that basis. The measurement was wrong twice over, and both faults were in the
  harness rather than in settle: prompts over ~64 characters were never submitted to Claude Code at
  all, and grok's answers were scored missing because the probe searched the byte stream, where
  repaints had split them. Re-measured with both fixed and detection moved to the rendered screen,
  the reply was correct in **27/27 claude turns and 18/18 grok turns, at every window including
  800 ms**. The longer window bought nothing and cost up to double the latency per call, so the
  default is 800 again. A send issued while the child was still producing output is still reported
  as `busy_at_send: true`, and `--wait-for-regex` on a *completion* marker remains the deterministic
  answer — but the "previous turn's answer" failure that motivated both was an artifact, and has not
  been observed since.
  What the evidence does not cover: two agents and 45 turns, both driving TUIs whose spinner runs for
  the whole turn, which is what makes byte silence mean "finished". A callee that goes quiet mid-turn
  for longer than the window still truncates.
- **A continuously animating child never settles.** Agents whose spinner runs for the whole turn
  (grok) are the easy case — byte silence genuinely means the turn ended. A child that animates while
  *idle*, or a long-running `top`-style command, never goes quiet and the send waits out
  `--timeout-ms` instead.
- **A settled reply is a byte stream, not a rendered screen — pass `--screen` when that matters.**
  A full-screen agent's answer is interleaved with its own redraws, so a 13-character reply arrives
  inside ~12 KB of repaints with the answer split across them; searching that reply for a string the
  agent plainly displayed fails. Measured against grok over three turns, the answer was absent from
  the byte stream 3/3 times and present in the rendered screen 3/3 times, which is why `--screen`
  exists. It is opt-in rather than the default because rendering is only correct for a child that
  actually paints a screen: for a cooked-mode shell the byte stream already is the answer, and the
  transcript remains the record of what happened rather than what is displayed.
- **`start` returns when the *supervisor* is ready, not when the child is.** An agent CLI takes
  seconds to boot, and input sent before it is listening is simply lost (or echoed by the
  still-cooked tty). Callers should wait for a readiness marker — via `read`, or a first `send`
  with `--wait-for-regex` — before driving a freshly started session.
- **Full-screen TUI agents produce redraw-heavy transcripts.** Driving one generates large volumes
  of ANSI repaint output; bound reads rather than pulling a whole transcript.
- **`read --tail` is close to useless against a TUI agent, and `--max-output` is the right tool
  there.** `--tail` counts newlines, and a full-screen agent's repaint stream is mostly escape
  sequences and carriage returns with very few newlines — `--tail 6` against a real agent returned
  effectively the entire 338KB transcript. This is inherent to line-counting, not a bug in the
  bound.
- **`clean_output` strips terminal control sequences but not terminal *semantics*.** With
  `TextSanitizer` widened (see the `parsers` change log) the escape codes are gone, but a
  full-screen agent's output is still a stream of repaints: the same line reappears many times and
  cursor-positioning is simply removed rather than replayed. It is readable, not a rendered screen.
  Reconstructing an actual screen would need a terminal emulator, which is out of scope.
- **`PromptScanner` duplicates the four-line last-line rule** that `PTYRunner#prompt_detected_in?`
  also implements. The honest shared home is `Parsers::PromptDetector`; extraction is deferred
  rather than done here so this change does not also rewrite the parsers contract.
- The in-memory transcript a supervisor keeps for cursor framing grows with session length.

