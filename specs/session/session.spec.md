---
module: session
version: 4
status: active
files:
  - lib/rune/session/store.rb
  - lib/rune/session/supervisor.rb
  - lib/rune/session/client.rb
  - lib/rune/session/attachment.rb
  - lib/rune/session/prompt_scanner.rb
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
| `write_to_child` | internal method | Writes the request text to the pty, terminated with a carriage return unless suppressed. |
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
| `compile_regex` | internal method | Compiles `--wait-for-regex`, returning nil when absent or invalid. |
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
| `start_name` | internal method | The explicit `--name` or a generated codename for a new session. |
| `start_rejection` | internal method | Returns the failure that blocks a start, or nil to proceed. |
| `running_conflict` | internal method | Returns a failure when the name already has a live supervisor. |
| `launch` | internal method | Creates session state, spawns the supervisor, and waits for readiness. |
| `spawn_supervisor` | internal method | Re-invokes rune's executable as the detached supervisor for one session. |

> Note: `conclude`, `handshake`, `with_raw_terminal`, `connect`, `name_base`, `socket_live?`,
> `serialized_launch`, `terminal_size`, `forward_resize`, `forward_pending_resize` and
> `with_resize_forwarding` are intentionally absent from the table above. They exist and are exercised by
> the suite, but SpecSync's Ruby extractor does not surface them from their position in the class
> body (rune#20 / spec-sync#479), and documenting an export it cannot see fails the contract check.
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
41. Nothing on the event-loop thread blocks on a write. Output to the child and to attached
    terminals is queued and drained when the destination reports writable, so a child that stops
    reading stdin, or a terminal that stops reading, costs memory and eventually its own connection
    — never the session's ability to pump the pty, evaluate a settle, or handle `stop`.
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
- **`stop` signals the pids recorded in `meta.json`.** If a supervisor was SIGKILLed and the kernel
  has since recycled its pid, `stop` could signal an unrelated process. Narrow, but real.
- **Settle is a heuristic.** A child that pauses mid-answer for longer than `--settle-ms` returns a
  truncated response. `--wait-for-regex` is the deterministic answer when the callee's prompt is
  known.
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
