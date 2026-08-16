---
module: session
version: 21
status: active
files:
  - lib/rune/session/store.rb
  - lib/rune/session/supervisor.rb
  - lib/rune/session/client.rb
  - lib/rune/session/attachment.rb
  - lib/rune/session/prompt_scanner.rb
  - lib/rune/session/pending_send.rb
  - lib/rune/session/transcript.rb
  - lib/rune/commands/session_command.rb
---
# Sessions (`rune session`)

## Purpose

Persistent, named PTY sessions that outlive a single `rune` invocation, so one agent CLI can drive
another conversationally instead of one-shot.

`PTYRunner` buffers a command's entire output and returns once; `PTYWatcher` streams live but
hard-refuses to run without a real human TTY on stdin. Neither can hold a REPL-shaped child open
across separate `rune` calls, so an agent had no way to "start `codex`, send a prompt, wait for the
answer, send a follow-up." This module adds that as a third execution model alongside the two
existing ones, rather than a mode bolted onto either.

Two primitives: a **session broker** (the child outlives the invocation) and **send-and-settle**
(send input, block until the child goes quiet, return exactly the output that send produced —
turning an async TTY into a synchronous request/response call).

`attach` is the human-facing half of the same idea: a named session is something you can come back
to yourself, take the wheel of interactively, and then leave running exactly where it was. Unlike
`rune watch`, which owns the child it spawns and ends when that child ends, detaching from a
session changes nothing about the child.

Deliberately a *broker*, not a message bus: rune holds sessions and addresses them by name, while
deciding who talks to whom stays the calling agent's job.

## Public API

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
| `Transcript` | class | One session's durable transcript: reconstruction, cursors across rotation, search and rendering. |
| `load` | class method | Reads a transcript log, returning the retained text and the bytes rotation dropped. |
| `text` | reader | The output the log still holds. |
| `dropped` | reader | Bytes of earlier output that rotation discarded. |
| `cursor` | instance method | Total bytes the child has produced, including what rotation discarded. |
| `from` | instance method | Everything from an absolute cursor onwards, as far as the retained text reaches. |
| `screen` | instance method | What a terminal would be showing. |
| `grep` | instance method | Lines matching a pattern with surrounding context, and how many matched. |
| `filter` | internal method | Applies `--grep` to a read, or reports an unparseable pattern. |
| `PendingSend` | class | One in-flight `send` and the decision of when it has been answered. |
| `observe` | instance method | Records that something other than the pty's echo has arrived. |
| `outcome` | instance method | The outcome for this tick, or nil to keep waiting. |
| `beyond_echo` | instance method | Returns the portion of a response past the pty's echo of the input. |
| `busy_at_send` | reader | Whether the child was still producing output when this send landed. |
| `client` | reader | The control connection waiting on this send. |
| `cursor` | reader | Transcript offset taken when the send was written, so the reply holds only its own output. |
| `compile_regex` | class method | Compiles `--wait-for-regex` with a bounded match budget, returning nil when absent or invalid. |
| `supports_regex_timeout?` | class predicate | Whether this Ruby can bound a single regex match. |
| `ECHO_GRACE_SECONDS` | constant | How long a prefix of the input may still be assumed to be the pty's echo. |
| `REGEX_MATCH_TIMEOUT` | constant | How long one `--wait-for-regex` match may run before the pattern is abandoned. |
| `REGEX_TIMEOUT_ERROR` | constant | The regex-timeout error class, or an unraised stand-in on Ruby without one. |
| `DEFAULT_TIMEOUT_MS` | constant | Hard cap on a whole send when the caller does not set one. |
| `SessionCommand` | class | Subcommand `rune session <start\|send\|read\|attach\|list\|stop\|archive>`. |
| `home` | reader | Returns the resolved session-state root for this store. |
| `default_home` | class method | Resolves `RUNE_HOME`, treating an empty value as unset, else `~/.rune`. |
| `valid_name?` | class predicate | Accepts only session names safe to use as a directory component. |
| `alive?` | class predicate | Asks the OS whether a pid exists; `EPERM` counts as alive, a bad value as dead. |
| `with_bindable_path` | class method | Runs a bind/connect against a path short enough for `sockaddr_un`, chdir-ing into the session directory when the absolute path is too long. |
| `sessions_dir` | instance method | Returns the directory holding every session. |
| `session_dir` | instance method | Returns one session's directory. |
| `meta_path` | instance method | Returns one session's `meta.json` path. |
| `MAX_LOG_BYTES` | constant | Ceiling on a session's transcript file before it is rotated. |
| `LOG_KEEP_BYTES` | constant | How much recent output a rotation keeps. |
| `rotate_output` | instance method | Rewrites the transcript keeping its recent tail, recording what was dropped. |
| `output_bytes` | instance method | Output bytes carried by one transcript line. |
| `tail_offset` | instance method | Byte offset of the first whole line within the keep bound of the end. |
| `output_bytes_from` | instance method | Output bytes carried by the region being kept, without parsing events. |
| `output_size` | instance method | Current size of a session's transcript file. |
| `rotate_log` | internal method | Rotates the transcript once it reaches the ceiling. |
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
| `transcript_bytes` | internal method | Total bytes the child has ever produced, which is what cursors count. |
| `slice_from` | internal method | Everything from an absolute cursor onwards, as far as the held window reaches. |
| `trim_transcript` | internal method | Drops output older than the attach backlog and older than any in-flight send. |
| `pending_text?` | internal predicate | True while a send's text is still queued for the pty master. |
| `undelivered_input?` | internal predicate | True while a previous send's text is queued and its terminator still owed. |
| `exit_status` | internal method | Normalizes a Process::Status into an exit code, mapping a signal to 128+n. |
| `UNDELIVERED_INPUT_ERROR` | constant | Error returned when a send arrives while previous input is still going out. |
| `await_exit` | internal method | Waits, bounded, for a cooperative shutdown to finish before force-killing. |
| `SUBMIT_DELAY` | constant | How long after a send's text the terminating carriage return is written. |
| `begin_pending` | internal method | Records the send cursor, settle window, regex, deadline, and echo for an in-flight send. |
| `resolve_pending` | internal method | Re-evaluates an in-flight send against new output once per loop tick. |
| `beyond_echo` | internal method | Returns the portion of a response past the pty's echo of the input, handling a partially-arrived echo. |
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
| `slice_from` | internal method | Returns transcript bytes at or after a cursor. |
| `compile_grep` | internal method | Compiles a `--grep` pattern, returning nil when it is unparseable. |
| `bound_size` | internal method | Applies `--max-output` or `--tail` to already-filtered text. |
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
| `ECHO_GRACE_SECONDS` | constant | How long after a send a prefix-of-input is still assumed to be the pty echo. |
| `ATTACH_BACKLOG_BYTES` | constant | How much existing transcript an attaching terminal is replayed. |
| `Attachment` | class | Connects a human terminal to a live session until the detach key is pressed. |
| `close_quietly` | internal method | Closes the control socket and prints the closing note, tolerating an already-closed socket. |
| `forward_keystrokes` | internal method | Sends typed bytes to the session, stopping at the detach key but still delivering what preceded it. |
| `render_output` | internal method | Writes one chunk of session output to the local terminal. |
| `DETACH_KEY` | constant | Ctrl-], the key that detaches and leaves the session running. |
| `ENDED_WHILE_ATTACHED` | constant | Message used when an attachment ends without the human detaching. |
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
| `screen_after` | internal method | Renders the settled screen for `send --screen`, client-side. |
| `busy_fields` | internal method | Whether the child printed within the settle window, and how long since. |
| `read_payload` | internal method | Builds the result body for a transcript read. |
| `ALIASES` | constant | Internal option keys whose user-facing flag is not their name with dashes. |
| `flag_name` | internal method | What to call a flag when speaking to the person who typed it. |
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

## Invariants

1. A started session's child survives both the launching `rune` process exiting and the launching
   terminal closing. The supervisor calls `Process.setsid` (rescued where unsupported) and is
   spawned with detached stdio, so it is not in the launcher's session or process group.
2. Exactly one supervisor process owns a given session's PTY master for that session's lifetime.
   There is no central daemon.
3. The control channel is a Unix domain socket (`control.sock`), not a FIFO: one JSON request line
   in, one JSON reply line out. A FIFO was rejected because a reader sees EOF whenever the last
   writer closes, and because it cannot return a reply to the caller.
4. Settle detection runs in the **supervisor**, which owns the output stream and therefore knows
   exactly when new bytes arrive — not in the client by tailing a file and guessing. The supervisor
   is single-threaded: a `send` that blocked its handler would stop draining the pty, stall the
   child on a full buffer, and guarantee the settle window never elapses.
5. `send` frames its response by taking the output cursor **at send time** and returning only bytes
   after it, so output already on screen before the send is never misattributed to it.
6. `send` returns on whichever comes first: no new output for `--settle-ms`, `--wait-for-regex`
   matching, the child exiting, or `--timeout-ms` elapsing. A `--timeout-ms` cap returns what was
   captured with `settled: false` and `timed_out: true` rather than failing.
7. The settle clock only starts once output arrives that is **not** the pty's echo of the input. A
   pty in cooked mode echoes whatever is written straight back, so counting the echo as "the child
   started answering" would settle a send on the caller's own words while the child was still
   thinking. The echo is still included in the returned output — dropping data silently would be
   worse than noise the caller can see.
8. Input is terminated with a carriage return, not a line feed, because that is what a real
   terminal sends for Enter. Raw-mode TUIs — which is most agent CLIs — listen for `\r` and ignore
   `\n`, so an `\n` terminator leaves the text sitting unsent in the child's composer. Cooked-mode
   children are unaffected because the line discipline translates `\r` to `\n` on input.
8a. That terminator is written **separately from the text, after a short delay**, so the child
   cannot receive both in one read. An agent TUI treats a large chunk arriving in a single read as a
   paste, and a carriage return inside a paste is a newline in the composer rather than Enter.
   Writing them together therefore typed the prompt and never sent it: measured against Claude Code,
   61 characters submitted and 82 did not, and every longer input sat unsubmitted while rune reported
   a clean settle — with an agent prompt almost always longer than that. Splitting the write fixes it
   for every length tried up to 262 characters, on claude, grok and agy alike. An outstanding
   terminator is flushed immediately if another send arrives first, because ordering matters more
   than the delay. The delay is measured from the last text byte actually going out, not from when
   the send arrived: draining and delivery happen in the same tick, so a deadline already past would
   fire microseconds after a backpressured write finished and land in the child's same read — the
   exact coalescing the delay exists to prevent.
9. `prompt_detected` is advisory metadata and **never** gates whether a call returns.
   `PromptDetector` matches shell-shaped prompts and is deliberately conservative, so it is usually
   `false` for exactly the agent REPLs this module exists to drive. Waiting for a prompt would hang
   on most real targets; settle-time is the primary signal and `--wait-for-regex` the deterministic
   escape hatch.
10. The child's pty is given an explicit window size. A detached session has no controlling terminal
    to copy dimensions from and an unset pty defaults to 0x0, which leaves a full-screen TUI agent
    rendering into nothing.
11. Output is decoded incrementally as UTF-8 via `UTF8StreamDecoder`, same as `PTYRunner`/
    `PTYWatcher`: incomplete multi-byte suffixes are retained across reads.
12. The transcript is an append-only NDJSON log using the **same event vocabulary `PTYWatcher`
    emits** (`start`, `output`, `exit`, each with a float `ts`), so one format serves both features
    and `tail -f` works on a live session.
13. `read` is served by replaying that transcript from disk rather than over the control socket, so
    it works identically for a live session and one whose supervisor has exited. Cursor offsets
    agree with `send`'s because both count the same concatenated decoded output.
14. `list` determines liveness by checking the recorded pids directly, never by trusting
    `meta.json`'s recorded state, so a supervisor that died without cleanup reports `dead`. A
    session that exited on its own or was stopped deliberately reports `exited`/`stopped` instead,
    so the stale case stays distinguishable from the ordinary ones.
15. `stop` kills and reaps both the child and the supervisor, leaves no orphan, and is idempotent.
16. A `start` that fails after spawning tears down the supervisor it spawned, so a failed start
    leaves no process holding a pty for a session the caller was told does not exist.
17. A child that has already exited is a *ready* outcome for `start`, not a startup error: a
    short-lived command legitimately finishes faster than `start` can observe it. This also keeps
    the missing/non-executable case consistent with `rune run` and `rune watch`, where 127/126 is
    the child's exit status on a successful `Result`.
18. Sessions are scoped to a project, so the same name in two checkouts is two different sessions
    and neither is reachable from the wrong directory. The project is the enclosing git working
    tree, or the directory itself outside one, resolved through symlinks so one tree cannot acquire
    two identities. `list` shows the current project only; `--all-projects` opts out.
19. `--name` is optional for `start` and required by every other subcommand. When omitted an unused
    `<tool>-<word>` codename is generated, so a session always *has* a name without an agent having
    to invent one — and so "the grok session" is unambiguous once there are two.
20. `archive` moves a stopped session out of the live namespace, freeing its name and keeping it out
    of `list`. An archived session is never reachable as a live one, and archiving refuses while the
    session is still running.
21. `stop` is observably complete when it returns: it waits for the signalled processes to actually
    disappear, so an immediately following command cannot still see the session as running.
22. `list` reports `idle_ms` and a `last_line` summary per session, read from the tail of the
    transcript rather than the whole file. This is what answers "is it stuck, and what was it last
    doing" when several agents run at once.
23. Session state lives under `RUNE_HOME` (default `~/.rune`). The session directory is `0700` and
    `meta.json`, `output.ndjson`, `supervisor.log`, and `control.sock` are `0600`, matching the
    owner-only precedent already set for `rune watch`'s default event log. Sessions live under
    `$RUNE_HOME/projects/<project>/sessions/`, archives under `.../archive/`.
24. Socket binding and connecting tolerate a long `RUNE_HOME`: `sockaddr_un` caps a path at 104
    bytes on macOS, which an ordinary deep home or any temp-dir-based test exceeds, so both ends
    bind relative to the session directory when the absolute path is too long.
25. Rune's own flags are recognized only before the first `--`, same discipline as `rune run`, so a
    wrapped command's identically named flags pass through untouched. `--name=NAME` and
    `--name NAME` are both accepted.
26. `attach` connects a real terminal to a live session: the child's output streams to the screen,
    local keystrokes are forwarded to it, and the current screen is replayed on connect so the
    terminal does not sit blank until the child next repaints. Detaching (Ctrl-]) leaves the child,
    the supervisor, and the session state untouched. `Ctrl-C` is deliberately *not* the detach key —
    it must keep reaching the child so an attached human can interrupt a runaway agent.
27. Output is broadcast to every attached terminal, and a terminal that goes away is dropped rather
    than allowed to break the event loop or kill the session.
28. A control client can never take the session down with it: a broken, reset, or half-written
    request closes that client only. Before this was enforced, an `ECONNRESET` unwound the event
    loop and the teardown path then SIGKILLed a perfectly healthy child.
29. A `send` that races the child's exit is answered with an error, not a dropped connection: the
    write can fail after the last `pump` observed the child as alive, and that must still leave the
    session's recorded state correct.
30. On an explicit stop the child is signalled before it is reaped. `Process.wait2` on an unsignalled
    long-lived child never returns, which previously left the supervisor wedged short of recording
    its own exit — visible only because the CLI force-kills afterwards.
31. `stop` bounds its cooperative shutdown and always proceeds to the force-kill. It is the
    documented recovery path for a session that is *already* misbehaving, so it cannot depend on the
    supervisor's normal reply guarantee.
32. Each supervisor lifetime owns exactly one transcript: starting a session under a previously used
    name resets it. Otherwise `send` cursors (which restart at zero with the new supervisor) and
    `read` offsets (which replayed the whole file) silently disagreed, and `read` returned a dead
    session's output as if it were this one's.
33. `--wait-for-regex` is matched against the output *beyond* the pty's echo of the input, never
    the raw slice. Matching the raw slice meant waiting for a marker you had just asked the agent to
    print returned the caller's own echoed words immediately — and since that is the normal way the
    flag is used, the documented deterministic escape hatch was the least reliable path available.
34. Echo suppression locates the echo within the slice rather than requiring it at the cursor. The
    cursor is taken the instant input is written, so bytes the child was already emitting (the tail
    of a previous prompt, a redraw) can arrive first. A partially-arrived echo is recognised by its
    *trailing* bytes matching the start of the echo, so a child that was mid-output when the send
    landed cannot turn a half-arrived echo into a reply.
35. An in-flight send whose caller goes away is released as soon as its socket reports EOF, rather
    than held until `--timeout-ms`. Otherwise one cancelled call locked the session for the whole
    timeout — two minutes at the default — refusing every later send.
36. `send` bounds its own wait client-side at the requested `timeout-ms` plus a margin. The
    supervisor normally guarantees a reply, but that guarantee does not hold when it is wedged, and
    without a ceiling a stalled supervisor became a permanently hung caller.
37. `start` treats a session as ready only when the supervisor process is actually alive, not merely
    when `meta.json` says `running` and the socket exists — a supervisor can record both and then
    die. It also fails immediately once the supervisor is gone rather than waiting out the start
    timeout for an answer that is already certain.
38. Teardown signals the child's process *group*. Agent CLIs routinely spawn workers, and signalling
    only the recorded pid left those running after `stop`, holding ptys and ports where they could
    collide with the next session for the same tool.
39. A control client can never take the session down: unexpected errors while handling a request
    close that client only, a request line that never completes is abandoned after a short bound,
    and a full disk while logging does not end the session.
40. Every directory rune creates under `RUNE_HOME` is owner-only, not just the leaf session
    directory, so the set of tools being driven and their session names is not world-readable.
41. Nothing on the event-loop thread blocks on a write — including control replies and the attach
    acknowledgement, which are queued like everything else and whose client is closed only once the
    reply has actually drained. Output to the child and to attached terminals is queued and drained
    when the destination reports writable, so a child that stops reading stdin, or a peer that stops
    reading, never costs the session its ability to pump the pty, evaluate a settle, or handle
    `stop`.
41a. Queued output for an *attached terminal* is bounded. A terminal whose queue exceeds the ceiling
    is dropped and its queue discarded, so one that accepts an attachment and then never reads
    cannot grow the supervisor's memory without limit. The ceiling applies to nothing else: not to
    the pty master, because a child that is slow to read is the session rather than a peer to be
    disconnected, and not to control replies, because a reply is an answer the caller is blocked on
    — discarding one reports a send as unreachable that in fact completed, and an agent then repeats
    a turn the child already did.
41b. Closing an IO unregisters it from every structure the event loop selects on. A closed
    descriptor reaching `IO.select` raises, which would unwind the loop and let teardown kill a
    healthy child, so the bookkeeping lives in one place rather than at each call site.
41c. A reply that has been queued is delivered before teardown, within a short bound. One
    `write_nonblock` takes at most a socket buffer's worth, so any reply larger than that is still
    partly queued when the loop exits — and the loop exits as soon as the child is gone and nothing
    is pending. Draining at teardown is what makes an answer survive the child that produced it; the
    bound is what stops a caller that has stopped reading from holding the supervisor open.
41d. A send whose write to the pty failed is reported as an error, never as sent. A queued write
    reports a dead master by marking the child finished rather than by raising, so a `--no-wait`
    send — which has no later settle to catch it — must check for that before answering.
41e. A supervisor that dies for any reason records why and leaves the session marked finished. It
    previously died silently: `meta.json` still read "running" with no exit code, no exit event was
    logged, and supervisor.log was empty, so nothing anywhere named the cause. The cause is written
    to the transcript as a `crash` event and to stderr, and the exit code becomes 70 (EX_SOFTWARE),
    distinct from any status the child could return.
41f. Echo tracking counts characters, never bytes. `String#index`, `String#[]` and `start_with?` are
    character-based, so mixing in a byte length both overshot the echo for non-ASCII input and asked
    for more characters than existed — the latter yielding nil and raising, which killed the whole
    supervisor and took the agent CLI with it. Multibyte output inside the echo grace window is the
    norm for an agent TUI (spinners, box drawing), not an edge case.
41g. A send issued while the child was still producing output is reported as `busy_at_send: true`.
    That is when the reply is most likely to be the previous turn's answer rather than this one's.
8b. A send is refused while a previous send's text is still going out. A `--no-wait` send sets no
   in-flight guard, so a second send can arrive mid-drain on a backpressured pty; accepting it
   would force the outstanding terminator out alongside undelivered text, putting both in one
   write and one read — the coalescing 8a exists to prevent, reintroduced by the guard that
   preserves ordering.
8c. Nothing that has already arrived can settle a send whose terminator has not gone out yet. While
   the input is unsubmitted only the hard limits apply — the deadline and the child exiting —
   because otherwise a small `--settle-ms`, or a regex matching a composer repaint, answers the
   send in the same tick its carriage return is written, reporting the screen as it was before the
   child was even given the line.
38a. `stop` lets the cooperative shutdown actually happen before force-killing, bounded. Acking the
   stop only sets a flag; the supervisor tears down on its next tick, and killing it in between
   meant the graceful path never once ran — an in-flight send's caller got "supervisor closed the
   connection without replying" instead of its captured output, and the control socket was left on
   disk.
38b. A session's recorded exit code reflects how the child actually died. `terminate_child` keeps
   the status it waited for; discarding it left `reap` to hit `ECHILD` on an already-reaped child
   and return a hardcoded 0, so a session killed on `stop` reported `exit_code: 0` as though it had
   exited cleanly.
38c. Killing a child's process group is not conditional on the leader still being alive. A group
   outlives its leader, so an agent CLI whose wrapper exits while its workers run left a live group
   behind a dead pid, and checking the leader first skipped the kill and orphaned exactly those
   workers.
41p. `read` reports `child_busy` and `idle_ms`, derived from the transcript's own timestamps so they
    work for a stopped session too. Without them a caller had to grep the callee's rendered UI for a
    busy marker, which is presentation rather than API. The flag says the child is *printing*, not
    that it is *working*: a child that backgrounded a command and went quiet reports false.
41o. `read --grep` filters the *cleaned* text, not the repaint stream. A full-screen agent's frames
    split words across escape sequences, so a pattern plainly visible on screen does not match the
    bytes. The reply carries `grep_matches`; an unparseable pattern is reported as `grep_error`
    rather than raised, because a bad regex from a caller is not a reason to fail a read.
41n. Rotation costs no measurable memory. It seeks to the cut point rather than scanning what it is
    dropping, reads the byte count each event already records rather than parsing the event, and
    copies with `IO.copy_stream` so the bytes never enter Ruby. The first implementation read the
    whole file and parsed every line twice, which put resident memory up 229MB the moment a
    rotation ran; streaming the lines but still parsing them still cost 96MB. Bounding the disk is
    not worth a memory spike larger than the problem it solves.
41m. A session's transcript file is bounded too, and rotation never makes a cursor lie. The
    in-memory window stopped resident memory tracking output, but the file kept every byte for the
    life of the session and `archive` moves it rather than pruning, so that cost outlived the
    session that paid it — a 150-second run at 500KB/s left 80MB behind permanently. Rotation keeps
    the recent tail and records what it dropped in a `truncated` event, so cursors stay absolute: a
    cursor taken before a rotation still names the same position in the stream, and `read` reports
    `dropped_bytes` rather than silently returning less than was asked for.
41j. The supervisor holds a bounded *window* of output, not all of it. Cursors remain absolute byte
    offsets into the whole stream, because `read` serves them client-side from the transcript file;
    the process itself only needs the attach backlog and whatever the current send has produced,
    and never trims past a live send's cursor however long that turn runs. A persistent session is
    the entire feature, so this is not a detail: measured before the bound existed, resident memory
    tracked output one-for-one — 27MB to 69MB in eighty seconds at 500KB/s — and never came down.
    After it, resident memory plateaus: over one 150-second run the last 60 seconds added 30MB of
    output and 0.16MB of memory.
41i. A `--wait-for-regex` match is bounded, and a pattern that exceeds its budget is abandoned with
    `regex_timed_out: true` rather than retried. Matching runs on the only thread, so a pattern that
    backtracks catastrophically blocks the loop: it cannot pump the pty, answer `stop`, or even
    check the send's own `--timeout-ms` — reproduced with `(a+)+\1$` against 60 `a`s, where the send
    was still blocked long after its 8s deadline. Retrying next tick would spend the budget again on
    a slice that only grows, so giving up on the pattern is the only outcome that ends.
41h. `--screen` on `send` and `read` returns the rendered terminal in addition to the byte stream,
    and is omitted entirely when not asked so the default result shape is unchanged. It is rendered
    in the calling process from the transcript file, never by the supervisor: re-rendering a long
    session on the one thread that must keep pumping the pty would trade a reporting improvement for
    a latency regression. `read --screen` renders the whole transcript rather than a `--since`
    slice, because a screen is the product of every escape sequence before it and replaying from a
    mid-stream cursor would show a screen the child never displayed.
41k. An attachment reports the way it ended, and never both ways at once. The note that the session
    is still running is printed only when the human actually detached; when the attachment ended
    because output stopped, the failure says so and points at `rune session list` rather than
    asserting that the child or supervisor exited, which the attachment cannot know. Reported from
    real use: a session that ended underneath produced "detached; the session is still running"
    and "Session ended while attached" in the same exit, one of which is always wrong.
42. Attaching propagates the terminal's real dimensions to the child and forwards SIGWINCH for the
    duration, over separate short-lived control connections — the attachment socket itself is a raw
    byte pipe after the ack, so a control frame written there would be typed at the child instead.
    When the last terminal detaches the child returns to the headless default, so a programmatic
    `send` renders the same whether or not a human attached in between.
43. Control connections that connect and never send are reaped. A silent peer is never readable, so
    it would otherwise sit in the client set for the life of the session, and enough of them would
    exhaust the supervisor's file descriptors.
44. `start` is serialised per session name by an exclusive lock held across the conflict check and
    the recording of a supervisor pid. Those are otherwise a check-then-act pair: two concurrent
    starts could both see the name as free, and the loser would unlink the winner's socket and
    orphan its child.
44a. A generated codename is chosen inside that lock, and contention retries another codename rather
    than failing. Choosing it outside meant two concurrent `start -- <tool>` calls could pick the
    same codename and the loser would fail on a name it never asked for, with many others free —
    which is precisely the parallel-agent case an optional `--name` exists to serve. An explicit
    `--name` still fails on contention: that name was the request.
45. `rune run` and `rune watch` behavior and result shapes are unchanged; this module is purely
    additive.

## Behavioral Examples

- `rune session start -- grok` returns immediately with a generated name such as `grok-amber`;
  `--name reviewer` picks one explicitly.
- `rune session list` shows only this project's sessions, each with idle time and the last line it
  printed; `--all-projects` widens it and `--archived` shows history.
- `rune session archive --name reviewer` files a stopped session away and frees the name.
- `rune session start --name grok -- grok` returns immediately with the session name and pid; the
  `rune` process exits while `grok` keeps running.
- `rune session send --name grok --settle-ms 800 "refactor auth.rb"` writes the prompt, waits for
  grok to stop producing output for 800ms, and returns just that reply.
- `rune session send --name s --wait-for-regex '\$ $' "ls"` returns as soon as the shell prompt
  reappears, without waiting out the settle window.
- `rune session send --name s --no-wait "^C"` writes without waiting for any reply.
- `rune session read --name grok --tail 50` returns the last 50 lines of transcript without
  sending anything.
- `rune session list` shows each session's state, distinguishing `running` from `dead`.
- `rune session attach --name grok` drops your terminal into the running agent; Ctrl-] detaches and
  leaves it running, so `rune session send --name grok ...` still works afterwards.
- `rune session stop --name grok` kills and reaps the session; running it twice succeeds both times.
- `tail -f "$RUNE_HOME/sessions/grok/output.ndjson"` follows a live session from another pane.

## Error Cases

| Condition | Behavior |
|-----------|----------|
| `--name` omitted, empty, or not matching the safe name pattern | `Result.failure` before spawning anything |
| Duplicate `--name` for an already-running session | `Result.failure` naming the conflict; the existing session is left untouched |
| Operating on an unknown session name | `Result.failure` suggesting `rune session list` |
| `send` against a session whose supervisor is gone | `Result.failure` reporting it is not running, with the recorded state and exit code |
| Control socket missing or unconnectable | `Result.failure` reporting the session is unreachable; `list` reports `dead`; `stop` still cleans up |
| A second `send` while one is already in flight | `Result.failure`; the in-flight send is unaffected |
| `pty` stdlib unavailable | `Result.failure`, same check and message class as `PTYRunner.pty_available?` |
| `--settle-ms`/`--timeout-ms`/`--tail`/`--max-output` not a positive integer | `Result.failure` before spawning anything |
| `--wait-for-regex` is not a valid regular expression | `Result.failure` before sending anything |
| `--timeout-ms` elapses before settling | Succeeds with the captured output, `settled: false`, `timed_out: true` |
| Wrapped command missing/non-executable | Session records exit code 127/126, same convention as `rune run` |
| `attach` with a non-TTY stdin | `Result.failure` pointing at `send`/`read` for non-interactive access |
| `attach` to a session that is not running | `Result.failure`, same check as `send` |

## Known Limitations

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
- **A supervisor that dies in the instant between spawning its child and recording that child's pid
  leaves the child untracked.** `abandon` can only kill what `meta.json` names, so such a child is
  reachable by nothing. The window now contains only the metadata write and cannot be closed
  entirely, since the pid does not exist until the spawn returns. In practice the pty master closing
  delivers SIGHUP, which ends most children; one that ignores SIGHUP is leaked.
- **One session is one supervisor process, which costs about 23MB and 27 descriptors.** The
  isolation is deliberate — a wedged agent takes down its own session and nothing else — but the
  price is a Ruby interpreter per session, paid up front. Measured with idle children: 24 sessions
  held 543MB and 648 descriptors, 60 held 1361MB and 1620, flat per session and unchanged across
  rounds of sends. Sixty agents therefore cost over a gigabyte before any of them does anything.
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

## Dependencies

- Ruby stdlib: `pty`, `socket` (Unix domain control channel — new to rune with this module),
  `io/console` (required with a `LoadError` rescue, same as `pty_watcher.rb`, for `IO#winsize=`),
  `io/wait`, `json`, `fileutils`, `shellwords`, `rbconfig`
- Internal: `UTF8StreamDecoder`, `OutputLimiter`, `Parsers::PromptDetector`,
  `Parsers::TextSanitizer`, `Result`, `Command`

## Change Log

- v1: Active spec — initial `rune session` broker and send-and-settle contract
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Add persistent named agent sessions: rune session start/send/read/list/stop, backed by a per-session detached supervisor holding the PTY, with send-and-settle so one agent CLI can drive another synchronously |
| 2026-08-14 | CHG-0029-fix-seven-session-defects-found-by-an-independent-grok-kimi-agy-review-wait-for: Fix seven session defects found by an independent grok/kimi/agy review: wait-for-regex matching the pty echo, a cancelled send locking the session, an unbounded client wait, start reporting success for a dead supervisor, teardown leaving agent workers alive, world-readable parent directories, and assorted robustness gaps |
| 2026-08-15 | CHG-0030-close-the-deferred-session-limitations-non-blocking-writes-so-a-stalled-child-o: Close the deferred session limitations: non-blocking writes so a stalled child or attached terminal cannot wedge the supervisor, terminal-size propagation on attach and SIGWINCH, idle control-connection reaping, and a lock file that makes concurrent start of one name safe |
| 2026-08-15 | CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent: Fix a bytes-vs-characters crash in session echo tracking that killed real agent sessions, make a dying supervisor record why instead of leaving the session marked running, and raise the send settle default from 800ms to 3000ms on measurement |
| 2026-08-15 | CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full: Render the terminal screen for session send and read, so an agent driving a full-screen agent can find the answer instead of searching every repaint frame |
| 2026-08-15 | CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot: Bound a --wait-for-regex match so a catastrophically backtracking pattern cannot wedge the supervisor past its own timeout |
| 2026-08-15 | CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag: Write a send's terminating carriage return as a separate delayed write, so an agent TUI submits the prompt instead of treating it as a pasted newline |
| 2026-08-15 | CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic: Restore the send settle default to 800ms and correct the 0.4.0 measurement, which was confounded by unsubmitted prompts and by searching a repaint-fragmented byte stream |
| 2026-08-15 | CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune: Fix two defects found by having grok and claude review this branch through rune itself: erase-line excluded the cursor cell, and backpressure defeated the terminator delay |
| 2026-08-15 | CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0: Fix six defects found by a read-only grok, kimi and agy council review of 0.5.0: renderer escapes and last-column cursor, a send accepted mid-delivery, a send settled before submission, stop killing before teardown, a false exit code, and a skipped process-group kill |
| 2026-08-15 | CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class: Extract the pending-send settle machine out of the supervisor into its own class, so the logic four review rounds kept finding bugs in is testable without an event loop |
| 2026-08-15 | CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session: Bound the supervisor's in-memory transcript to a window, so a persistent session's resident memory stops tracking output one-for-one |
| 2026-08-15 | CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e: Fix an attachment reporting both that the session is still running and that it ended, in the same exit |
| 2026-08-15 | CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi: Bound a session transcript on disk as well as in memory, rotating it while keeping cursors absolute |
| 2026-08-15 | CHG-0045-record-what-running-many-sessions-at-once-costs-measured-across-24-and-60-concu: Record what running many sessions at once costs, measured across 24 and 60 concurrent supervisors |
| 2026-08-15 | CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai: Rotate a session transcript without reading it: seek to the cut and copy the tail, instead of parsing every line |
| 2026-08-15 | CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim: Add read --grep for searching a long transcript, and correct what the docs claim about prompt_detected and settled |
| 2026-08-15 | CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process: Report child_busy and idle_ms on read, and document that exit_code is a process status rather than a verdict on the work |
| 2026-08-15 | CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an: Extract the transcript out of SessionCommand: reconstruction, cursors, search and rendering are one subject |
| 2026-08-16 | CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha: Four-agent pre-1.0 review: nine bugs fixed, and fifteen documentation claims that were wrong |
