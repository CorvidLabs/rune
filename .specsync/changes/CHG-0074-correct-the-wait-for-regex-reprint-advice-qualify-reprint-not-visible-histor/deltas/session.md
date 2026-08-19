## MODIFIED

### SPEC SECTION Invariants

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
6. `send` returns on whichever comes first, and **which conditions race depends on whether a
   pattern was given**. Without `--wait-for-regex`: no new output for `--settle-ms`, the child
   exiting, or `--timeout-ms` elapsing. With one, quiet is **not** among them — the send answers on
   a match, the child exiting, or `--timeout-ms`, and `--settle-ms` has no effect on it.

   That is deliberate and was a fix, not an oversight. Quiet used to answer a regex send, so
   `--wait-for-regex DONE --settle-ms 800` returned `settled: true, matched: nil` at 800ms against a
   child that printed DONE five seconds later, 3/3 — and the documented workaround for the settle
   defect did not work at the default settle window. An earlier version of this invariant listed
   four racing conditions, and `--help` described the flag as an accelerator that returns "without
   waiting out the settle window"; both read as though settle still applied, and callers lost whole
   `--timeout-ms` windows to the difference.

   A `--timeout-ms` cap returns what was captured with `settled: false` and `timed_out: true` rather
   than failing. A regex send additionally reports `matched: false` there, so the field is present
   however the send ended and a caller reading it as a tri-state is not told `nil` for both "no
   match" and "not a regex send".
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
   on most real targets; settle-time is the primary signal and `--wait-for-regex` the escape
   hatch, provided the child will not emit that pattern again as a reprint of earlier output
   before this turn's answer.
10. The child's pty is given an explicit window size. A detached session has no controlling terminal
    to copy dimensions from and an unset pty defaults to 0x0, which leaves a full-screen TUI agent
    rendering into nothing. Every size the supervisor *changes* the child to is recorded in
    `meta.json`, so a process that is not the supervisor can render the transcript at it. The
    starting default is deliberately not recorded: an absent size renders at exactly those
    dimensions anyway, and writing it would put a second meta write immediately after
    `record_running`, against the parent's own update during launch. Only a size that actually
    changed is written: a human dragging a window edge emits a SIGWINCH per frame, and each one
    would otherwise rewrite the whole file on the thread that must keep pumping the pty.
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
34. Echo suppression locates the echo within what has arrived rather than requiring it at the
    cursor. The cursor is taken the instant input is written, so bytes the child was already
    emitting (the tail of a previous prompt, a redraw) can arrive first. Until a copy of the input
    is found, nothing is offered to the pattern for `ECHO_GRACE_SECONDS`; past that window what has
    arrived is offered *provisionally*, because a child that never echoes at all would otherwise
    hang every send to it. Provisional means the search continues: a child whose echo lands a
    second late is not a child that did not echo, and when its copy turns up the offer is withdrawn
    and the boundary set behind it. Output offered provisionally is therefore never latched as "the
    child has spoken" — abandoning the search at the grace window instead was measured to settle
    such a send on the echo alone, 0.8s after it arrived and a second before the child had said
    anything of its own.
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
40a. `meta.json` is replaced, never truncated in place: the JSON is serialised first, written whole
    to a private per-pid temp path, and renamed over the target, the same shape `rotate_output`
    already uses. Every other rune process answers "does this session exist, and is it alive?" out of
    this file with no lock to take, so an instant where it is short or empty is an instant where
    `send` says "No such session", `list` reports `state: dead`, and `read --screen` loses the
    recorded geometry. That was rare while meta was written a handful of times per session and stops
    being rare once the winsize is recorded — a human dragging a window edge emits a SIGWINCH per
    frame. Measured through a real attach dragged across 250 window shapes in 7.5 seconds while
    another process did exactly what `alive_session` does: 90 of 294,728 reads came back unreadable
    with the truncating write and 0 of 312,582 with the rename. The temp path carries the
    writer's pid because two processes write this file — the CLI records `state`/`supervisor_pid`
    while the supervisor records `state`/`child_pid` and the winsize — and a shared temp path would
    let them interleave into one corrupt file that then got renamed into place.
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
41r. A mistyped flag is refused, not typed at the child. `send --name=x --settle_ms 500 'echo
    HELLO'` matched no flag, so the flag, its value and the input were joined with spaces and
    written to the child, which answered `status: ok`. Two limits keep the refusal from catching
    anything that works: nothing after the first `--` is examined, so `send --name=x -- --settle_ms`
    still types `--settle_ms`; and nothing after the first operand is examined, so
    `start --name=x claude --resume` and `send --name=x git log --oneline` are untouched. `---` and
    `--- section ---` are not flag-shaped and are sent as typed.

41q. A `--grep` pattern that will not compile selects nothing, and the read returns nothing. It used
    to return the entire transcript under `status: ok` — the exact opposite of the same read with a
    valid pattern that matches nothing, so a caller that did not read `grep_error` saw every line as
    though it had matched, at the maximum possible cost. `grep_matches` is absent rather than `0`,
    because no search happened. The read still succeeds: `cursor`, `dropped_bytes`,
    `prompt_detected`, `idle_ms`/`child_busy` and `screen` have no bearing on the pattern, and a
    failure would take the cursor the caller needs down with them. `send` still rejects a bad
    `--wait-for-regex` outright, because there the pattern decides when to return.

41o. `read --grep` filters the *cleaned* text, not the repaint stream. A full-screen agent's frames
    split words across escape sequences, so a pattern plainly visible on screen does not match the
    bytes. The reply carries `grep_matches`; an unparseable pattern is reported as `grep_error`
    rather than raised, because a bad regex from a caller is not a reason to fail a read.

    Three limits, all measured, that "filters the cleaned text" does not make obvious. Overwritten
    history still matches and comes back as a clean standalone line, so a match can be text the
    screen has not shown since. A cursor-painted frame contains no line breaks at all, so it is one
    grep line: `--context` is inert and a single match returns the whole frame under a plausible
    `grep_matches: 1`. And a pattern anchored to what is visible on screen can return
    `grep_matches: 0`, because adjacency on the screen is not adjacency in the stream. The flag's
    own help claimed it matched "the rendered text rather than the repaint stream", which is the
    opposite of what it does; that is corrected. Use `--screen` when the question is what is
    currently displayed.
41p. `--grep` searches the slice `--since` selected, not the whole transcript. It was handed the
    slice and then discarded it, so `--since` had no effect on a grepped read: a read from a cursor
    recorded after the first line still returned that line, and `grep_matches` counted it. A caller
    paging with `--since=<last cursor>` got the entire history back on every page, under a count
    that looked like it had filtered. Context windows are taken within the slice, so a match on its
    first line has no preceding context to show — which is the same thing `--since` already means
    for every other field in the reply.

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
41w. A transcript write that fails is *recorded*, not merely survived. The in-memory cursor has
    already advanced — those bytes really were produced — so a hole nothing accounts for makes every
    cursor `send` hands out unresolvable by `read`, permanently and silently. Reproduced on a full
    filesystem by the durability prototype this is taken from, and carried over rather than
    re-derived here: `send` answered `cursor: 1849946` while `read` reported 187221 with
    `dropped_bytes` nil, `read --since=1849946` returned "" for the rest of the session, and freeing
    the disk made it worse because logging resumed over the hole without a word. Output that no
    write could record is carried and emitted as a `truncated` event by the next write that
    succeeds — the same vehicle rotation already uses — so `read` resolves a pre-hole cursor again
    and reports `dropped_bytes`. While the hole is still owed there is nowhere on disk to record it,
    so the supervisor reports `transcript_gap_bytes` on `status` and on the `send` reply that hands
    out the unresolvable cursor; that is the only place the skew is known at all.
41x. "Recorded" means exactly "its own write returned". A write that fails part-way leaves a
    fragment, and a fragment can be a *complete* JSON record that merely never got its newline —
    which a later append would silently terminate, counting a gap twice. So each record is written
    on its own, and the first record after a failure is preceded by `TORN_MARKER`, which makes any
    dangling fragment unparseable. Swept here across every split point of the record carrying a gap:
    0 disagreements in 91 cases between the reconstructed cursor and the supervisor's own.
41y. A cursor is mapped through *each* dropped region, not past one running total. `since - dropped`
    is correct only while the dropped region is a **prefix** of the stream, which rotation
    guarantees and a failed write does not: a hole in the middle shifts output the cursor is not in
    front of, and every cursor issued before the hole then resolves |hole| bytes early — already
    delivered output, handed back as new, which re-fires prompt detection and every "did my command
    finish" check built on it. Measured on 25 chunks x 4000B, a 48_000-byte mid-stream hole and 25
    more (cursor 248_000, dropped 48_000): `from(100_000)` returned 148_000 bytes beginning at the
    start of the stream, 48_000 of them already delivered, against 100_000 beginning after the hole.
    Each region is recorded as (retained offset, cumulative dropped) at load, a cursor landing
    inside one clamps **forward** to its end — those bytes are gone either way, and later output is
    honest where earlier output is not — and a single prefix collapses to exactly the old
    arithmetic, byte for byte, at every probe of every rotation case.
41z. A rotation counts exactly the bytes the reader will reconstruct from the region it keeps, since
    the head event it writes is `total_output - kept`. Two ways that was wrong, both permanent and
    silent, both measured here on ~11MB transcripts rotated with the region in the kept tail: a
    `truncated` event inside the tail was not counted, so a hole recorded mid-stream was counted
    twice and every later cursor sat **+400_000** bytes past the end of the stream; and a fragment
    left by a torn write *was* counted although `Transcript.load` cannot parse it, so every later
    cursor sat low — **-4096/-16384/-40960** for 1/4/10 torn writes, scaling with the
    outage because `TORN_MARKER` terminates each fragment into a countable line of its own. That
    this is worse than 0.8.0's flat -4096, where a fragment and the record after it merged into one
    unparseable line, is the prototype's measurement carried over and was not re-derived here. A
    real outage moves both dials at once and they do not cancel: a torn write plus the gap it opened
    measured **+16384**. All four cases, and a healthy transcript that must not move at all, measure
    0 once a line counts only if it is a whole record and a `truncated` in the tail counts as the
    bytes it names. The test is the line's last byte rather than a parse, because parsing the kept
    region cost 96MB per rotation (41n); `TORN_MARKER` is what makes that exact, since a fragment it
    terminated ends in `n` and cannot parse either. The one shape a byte test cannot decide is a
    fragment the file simply ends on, of which there is at most one, so a line with no trailing
    newline is parsed outright: swept over every split point of every record shape, with braces,
    quotes, escapes and the marker's own bytes inside the payload, 0 disagreements in 1760 cases,
    against 10 with that branch removed.
41j. The supervisor holds a bounded *window* of output, not all of it. Cursors remain absolute byte
    offsets into the whole stream, because `read` serves them client-side from the transcript file;
    the process itself only needs the attach backlog and whatever the current send has produced,
    and never trims past a live send's cursor however long that turn runs. A persistent session is
    the entire feature, so this is not a detail: measured before the bound existed, resident memory
    tracked output one-for-one — 27MB to 69MB in eighty seconds at 500KB/s — and never came down.
    After it, resident memory plateaus: over one 150-second run the last 60 seconds added 30MB of
    output and 0.16MB of memory.
41aa. Resolving an in-flight send costs the bytes that just arrived, never everything the turn has
    produced. Both halves of that were quadratic and both starved the pty drain, because the same
    thread does the copying and the pumping. The pattern was matched against the whole accumulated
    slice on every 4 KB read — 66.69s inside the echo search and 17.65s inside the match, for a
    12 MB turn that then reported `settled: false, timed_out: true` at 90.51s while holding 11.46 MB
    of a 12.00 MB answer whose completion marker the child had already printed. Underneath it, the
    supervisor built that slice with `byteslice`, which marks a mutable String *shared*, so the very
    next `<<` copied the whole transcript to make it independent again: one copy of the turn per
    read, 85% of a sampled 24 MB profile, and the reason a plain `send` with no pattern at all was
    superlinear too (48 MB in 118.87s). The send is now fed what `append` just received and holds
    bounded state; the full slice is built once, on the tick that answers it. Measured after: 12 MB
    settles `matched: true` in 0.98s with all 12.15 MB read, and 48 MB in 3.37s.
41ab. A `--wait-for-regex` pattern is matched against the most recent `MATCH_WINDOW_BYTES` of
    post-echo output, with each scan resuming `MATCH_SPAN` characters behind where the last one
    stopped. That resumption is the guarantee worth stating: any single match up to `MATCH_SPAN`
    characters long is always found, because on the tick that completes it the scan still begins
    behind where it started. A single match that must span more than that is never found — the
    deliberate cost of the bound, documented in `docs/sessions.md`. The scan is resumed by position
    rather than against a substring so that `\A` keeps meaning the start of the child's answer and
    cannot be satisfied by wherever the window happens to begin. None of this bounds the reply:
    `output` remains everything the child produced for the turn.
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

    `--screen` is not bounded by the read filters — not `--since`, `--tail`, `--grep` or
    `--max-output`. It is bounded by geometry instead, at most `screen_rows x (screen_cols + 1)`,
    and both dimensions come back in the same reply: a 219,941-byte transcript rendered to 2,113
    bytes, and a dense 40x120 frame is 4,839 bytes of ASCII or 7,239 of CJK. So a caller passing
    `--max-output` does get a bounded reply, just bounded by a different rule than the one they
    named — the defect is surprise, not unboundedness, which is why two reporters declined to file
    it. Applying the byte bound to the render was measured and rejected: rendering only the bounded
    bytes paints a discarded frame plus rune's own elision marker into the child's screen and lost
    9 of 10 answers, and truncating the rendered string is a no-op where it matters while needing a
    second `omitted_bytes` in one reply, which 50a forbids.
41s. `--screen` renders at the size the child's pty is actually set to, and reports it as
    `screen_rows`/`screen_cols`. The size is not a constant — the child starts at
    `DEFAULT_ROWS`x`DEFAULT_COLUMNS`, `attach` resizes it to the terminal that took it over, and
    `detach` restores the default — so the supervisor records the current winsize in `meta.json`
    whenever it changes it and the caller's process reads it back. Rendering at a fixed default
    while a human was attached from any other shape produced a screen nobody ever saw: measured
    against a child that lays out against its winsize, resized over the control socket to 30x100,
    with pyte 0.8.2 and GNU screen 4.00.03 replaying the same transcript bytes as independent
    oracles that agreed with each other exactly, **36 of 37 rows differed before and 0 of 31 after**.
    Repeated at 24x80 (30/31 before, 0/25 after), 12x40 (18/19, 0/13) and 50x200 (50/51, 0/51); at
    40x120, where the two sizes coincide, 0 wrong both ways. Repeated again through a real
    `rune session attach` in a real 30x100 pty, comparing against the bytes that terminal itself
    received: 29 of 30 rows differed before, 0 of 30 after.
    A size that was never recorded or that is not a usable terminal (hand-edited meta, a pty whose
    size was never set) falls back to `DEFAULT_ROWS`x`DEFAULT_COLUMNS`, which is exactly the previous
    behaviour and is also the size `apply_window_size` gives a child nobody has attached to.
41t. A caller can tell a recorded size from the fallback, and `screen_rows`/`screen_cols` are not how.
    A session attached from a 40-row terminal records exactly the fallback numbers, so the pair
    cannot carry the distinction; `screen_size_recorded` is the field that does. It is true only when
    the resolved size is what `meta.json` actually held — a value that was clamped, discarded or
    absent reports false, because what is being reported then is a default and not a fact about the
    child.
41u. A winsize arriving over the control socket is clamped where it is recorded, not where it is
    rendered. A pty's winsize fields are 16-bit, so `{"op":"resize","rows":65535,"cols":65535}` is
    accepted by the kernel; recording it unbounded would make every later `--screen` drive a grid
    that size for the rest of the session's life, reinstating one layer up the denial of service
    behavioural point 12 of `parsers` clamps at the renderer. Measured on a 683KB `\e[999L`
    transcript, one `read --screen`: **0.76s at 40x120, 17.72s at the 1000x2000 the renderer would
    have clamped 65535 to, and 3.41s at the `MAX_ROWS`x`MAX_COLUMNS` ceiling** that is now the most
    a client can ask for. The pty is clamped too, so the child, the record and the render agree —
    recording a size the child never had is the bug this whole point exists to fix. The residual
    cost at the ceiling is the renderer's per-row cost for line-insert and scroll operations, which
    a genuinely 300-row terminal pays identically; it is bounded, not eliminated.
41v. The whole retained transcript is rendered at the *current* size, including output painted before
    a resize. That is what an attaching terminal itself shows, because the supervisor replays the
    backlog into it at its size — verified through a real attach at 0 of 30 rows wrong even for a
    child that ignores SIGWINCH entirely. The unresolved case is a child that never repaints *and*
    whose pty is resized under an already-attached terminal, where that terminal is reflowing glyphs
    it has already drawn. There is no reference answer to match: fed the bytes that terminal
    received and shrunk mid-stream from 40x120 to 24x80, GNU screen 4.00.03 kept only the cursor row
    and pyte 0.8.2 kept nothing at all, and the two disagreed with each other on one row of the
    little they retained. Rune keeps the content and re-flows it, which differs from both (24/24
    against pyte, 24/25 against GNU screen) where the old fixed 40x120 render differed in 15 — but
    that score is an artifact of a mostly blank screen coincidentally matching mostly blank oracles,
    not evidence that the fixed size was closer to what anyone saw. Documented rather than tuned to
    whichever emulator was measured last.
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
46. A rotation that cannot be written costs only the rotation. `rotate_output` closes the caller's
    handle after the replacement is in place, never before, and removes any half-written temp file
    on the way out. Closing first meant a failure anywhere later left the supervisor holding a
    closed handle it had no idea was closed, and `log_event`'s own rescue then swallowed every
    subsequent write — recording stopped silently and permanently. Measured on a real EACCES
    directory: 200 further events left the transcript 564,000 bytes behind the cursor, and restoring
    write permission widened the gap to 654,000 rather than resuming. A failed rotation is then
    backed off for `ROTATE_RETRY_SECONDS` rather than retried on the next event, because
    `@log_bytes` stays over the ceiling and every attempt seeks and scans the tail it means to keep
    before it discovers it cannot write — 8,388,576 bytes in 4.8ms at the real bound, on the single
    thread that also drains the pty.
46a. A transcript write that fails is recorded, not merely survived. The in-memory cursor has
    already advanced, so a hole nothing accounts for makes every cursor `send` hands out
    unresolvable by `read`, permanently — reproduced with RUNE_HOME on a full 20MB ramdisk, where
    852,000 bytes of output went unrecorded under `dropped: 0` and freeing the disk resumed logging
    over the hole without a word. The lost byte count is carried and emitted as a `truncated` event
    by the next write that succeeds, the same vehicle rotation uses, so a pre-hole cursor resolves
    again and `read` reports `dropped_bytes` rather than silently returning less. Re-measured on the
    same ramdisk: skew −873,000 during the outage and 0 after recovery. While the hole is still owed
    there is nowhere on disk to record it, so `send` replies and `status` carry
    `transcript_gap_bytes` — the only window in which the skew is knowable at all.
46b. A write that fails part-way leaves a fragment, and a fragment can be a complete JSON object
    that merely never got its newline — which, once more text is appended, silently swallows the
    next good record too. Measured on that ramdisk: 280 of 300 writes failed and one left a
    4,938-byte line parsing as neither record. `TORN_MARKER` is therefore written ahead of the first
    record to follow a failure, so the fragment terminates into a line that cannot parse and only it
    is lost. `Store#whole_record?` and `Transcript.load` must then agree exactly on which lines
    count, because one feeds a rotation's head event and the other reconstructs the stream: the test
    is a byte comparison (records are one line ending `}`, a marked fragment ends `n`) with the
    file's unterminated last line parsed outright, since that is the one shape bytes cannot settle.
    Swept over every split point of 36 record shapes with braces, quotes, escapes, raw newlines and
    the marker's own bytes in the payload: 8,832 lines compared, 0 disagreements, and 10 cases the
    byte test alone would have got wrong on that last line.
47. Teardown kills the child before it records the session as exited. `cleanup` used to write
    `state: 'exited'` first, so a supervisor dying in that window left a concluded record beside a
    live process holding a pty. `conclude` already had this order on the normal path; the abnormal
    one now matches it. `terminate_child` is idempotent and each teardown step keeps its own rescue,
    so a child that will not die still gets the record written after it.
48. A child that outlived its supervisor is *reported*, never made a reason to refuse. `list` and
    the `archive` reply carry `orphaned_child_pid` when a session's supervisor is gone and its
    recorded child is provably still running. Nothing is blocked and nothing is signalled; the
    operator is told the number while it is still reachable, because archiving moves the session out
    of the live namespace and that reply is the last place the pid appears.
48a. "Provably" means the pair (pid, start time), not the bare pid and not its process group. The
    supervisor records the child's start time as `ps` reports it, under `LC_ALL=C` because `lstart`
    is formatted through the locale (`Fri Aug 14 13:41:13 2026` under C, `ven. 14 août 13:41:13
    2026` under fr_FR). A bare `alive?` answers yes for any process that recycled the number. Asking
    the process group is not a fix and was measured to be actively wrong in both directions: 1,222
    of 1,390 live processes on the development machine (87.9%) lead their own group, and 130 of the
    200 most recently allocated pids (65.0%), so a group question answers "alive" for a stranger
    about as often as a bare pid does — while a child that is *not* a group leader is missed
    entirely. An earlier design refused the archive on that test and directed the caller to
    `rune session stop`, which SIGKILLs the recorded pid's whole process group; two runs of it
    killed unrelated live groups.
48b. The recorded `state` is deliberately not consulted. A check that skipped sessions recorded
    `exited`/`stopped`/`failed` was blind to exactly the case invariant 47 describes. `state` is a
    claim by a process that is now dead; the pid/start-time pair is evidence.
48c. Where the question cannot be asked soundly, the answer is silence rather than a guess. A
    session with no recorded `child_started_at` — started before the field existed, or by a
    supervisor that died in the window between recording the pid and recording the start time —
    reports nothing, even if its child is in fact alive.
49. `rune run` and `rune watch` behavior and result shapes are unchanged; this module is purely
    additive.
49a. The child ends up at the default geometry, but may observe `0x0` first. `PTY.spawn` returns the
    master only once the child is already running, so `apply_window_size` cannot land before a child
    that reads its winsize immediately; such a child is corrected by the SIGWINCH that follows.
    Observed on a Ruby 3.1 CI runner as `SIZE:[0, 0]` then `RESIZED:[40, 120]`, where every other
    version won the race. Closing it would mean opening the pty, setting its size, and spawning onto
    the slave by hand instead of using `PTY.spawn` — a change to the spawn path that has not been
    measured, so this is recorded as a limitation rather than fixed in a hurry. A child that reads
    its size once at startup and never handles WINCH is the case that loses.
51. A read stops at the last **complete** escape sequence, not at the last byte, and its cursor
    stops there too. `strip_ansi` only matches sequences that terminated, so a sequence split
    across two pty reads was wrong at both ends: the fragment was delivered as visible text, and
    the cursor advanced past it so the *next* read saw the remainder headless and stripped nothing.
    Measured against a child that printed `READY`, then `\e[3`, slept, then `1mRED\e[0m`:

        read (no flags)            clean_output "READY\n\e[3"    cursor 10
        read --since=10 --screen   clean_output "1mRED\n"        screen "READY\nRED"

    The second reply contradicts itself: `clean_output` says the child printed `1mRED` and `screen`
    says `RED`, from one invocation. The child printed `RED`. Withholding the fragment from both the
    text and the cursor fixes both halves — the next read starts at the ESC and sees the sequence
    whole. Nothing is lost: the bytes stay in the transcript and are returned once the sequence
    completes, and a child that opens one and never closes it withholds those bytes indefinitely,
    which is exactly what a terminal does with them.

51b. A `--since` that lands inside a multi-byte character snaps **forward** to the next character
    start, rather than delivering U+FFFD for the orphaned continuation bytes. `--since` is a raw
    byte offset a caller can compute (`--since=$((cursor-200))`), so unlike a cursor rune itself
    issues — those never land mid-character, because `UTF8StreamDecoder` holds a trailing incomplete
    sequence — it can start inside a 2-, 3- or 4-byte character. `.scrub` then replaced each
    orphaned continuation with U+FFFD under `status: ok`, and `--since=1` on `こY` (E3 81 93 59)
    returned **more** bytes than `--since=0` because two continuation bytes became two 3-byte
    replacement characters. A consumer could not tell rune's slicing from a U+FFFD the child
    emitted. Snapping forward drops the split character (it is not available from this offset) and
    invents nothing. Cursors rune hands out, and a `--since` that already sits on a character
    start, are unchanged.

51a. `list`'s `last_line` is summarised from the reassembled tail, not from the last event alone. A
    pty read boundary is neither a line boundary nor a sequence boundary, so an event-at-a-time
    summary stripped nothing from either half of a split sequence and reported `1mRED` where the
    child had displayed `RED`.

50. `--max-output` and `--tail` bound `send` as well as `read`. Both flags were parsed for every
    subcommand and applied only by `read`, so `send --max-output=120` returned everything under
    `status: ok` — a caller that asked for a bound was told it succeeded and did not get one.
    `send` is the worst place for that gap: it is the call an agent makes most, and one turn of a
    full-screen TUI is megabytes. Bounding happens in the command rather than the supervisor
    because the cap is one caller's presentation choice; the transcript, the cursor, and every
    attached client still see the whole stream.
50a. `clean_output` is derived from the *bounded* raw text, not bounded separately. Bounding the
    two independently lets them describe different windows of one reply and leaves
    `omitted_bytes` true of only one of them. This is what `read` already does.
50b. `--max-output` and `--tail` are mutually exclusive on every session subcommand, with the same
    message `rune run` has always used. Accepting both applied whichever `bound_size` tested
    first, so the caller silently got the other one.

52. A launch that never happened returns `status: error`. `start` with a command that is not on
    PATH used to return `status: "ok"` with `state: "exited"` and `exit_code: 127`, so a caller
    checking the field whose entire job is to say whether the call worked saw success. It was
    documented as "check `state` instead", which is the wrong shape of answer — an envelope should
    not need a footnote to be read correctly. Reported from a 22-minute real drive, where it cost
    an hour.

    Only 127 fails, and that is deliberate: `start -- true` exits 0 immediately and is a
    *successful* launch of a program that had nothing to do, so treating any prompt exit as failure
    would break every short-lived child. 127 is the shell's "command not found" — the one case
    where the child never ran.

    The session record is kept rather than deleted. `start` failing loudly is the fix; removing the
    transcript that shows why would trade one quiet failure for another, and `list` reporting the
    session as dead with `exit_code: 127` is the diagnosis a caller needs.

53. An error naming a session says where the session actually is, when it is somewhere. A
    session started in one directory and read from another got `No such session`, and the remedy
    that error printed — `rune session list` — is scoped to the caller's own project and returns
    nothing, which reads as proof the session died. rune knew the answer the whole time:
    `--all-projects` finds it. It has now caught three separate readers, two of whom had read the
    guide's warning about directory scoping first, which is when a documented gotcha stops being a
    documentation problem.

54. `abandon` waits for the kill it issues to land before recording the abandoned session as
    failed, using the same `await_death` `stop` already relies on. SIGKILL is asynchronous: without
    waiting, a launch that failed and abandoned its supervisor could still show as `running` in the
    very next `list`, because `describe` recomputes state from real process liveness rather than
    trusting the record `abandon` writes — deliberately, since a supervisor killed with SIGKILL
    never updates its own meta and a recorded state is routinely stale. `stop` hit this exact shape
    first (its own `await_death` comment: "the very next command saw the session as running";
    `archive` straight after `stop` failed on it) and `abandon` had the identical fire-and-kill
    shape without the fix. Caught by a CI runner slow enough to make the race land, after passing
    locally.


### SPEC SECTION Known Limitations

- **An orphaned child can only be reported when its identity was recorded.** The report rests on
  matching the recorded `child_started_at` against the live process's start time. Sessions started
  before that field existed report nothing, and so does a session whose supervisor died in the
  window between recording the child's pid and recording its start time — `record_running` is
  deliberately still the first write, because a pid on disk matters more than an identity for it.
  Silence therefore means "not known to be orphaned", never "known not to be".
- **`lstart` resolves to one second.** Two processes wearing the same pid within a single second
  would be indistinguishable to the identity test. Real pid reuse cannot be that fast — the pid
  space has to wrap first, measured at 2,482 pid numbers consumed per second under a sustained spawn
  loop on the development machine, so ~40 seconds for the 99,999-pid space — but the bound is a real
  one and not a proof.
- **The report needs `ps`.** Where `ps` is missing or refuses, `process_start_times` returns nothing
  and every session reports no orphan. That is the safe direction (silence, not a false accusation),
  but it is silent about being unavailable.
- **A single line of 1024 bytes or more is silently discarded by a cooked-mode child's terminal.**
  This is `MAX_CANON`, a tty limit rather than a rune bound: the line discipline cannot assemble a
  longer canonical line, so it drops it and the child never sees it. Measured exactly — 1023 bytes
  arrive, 1024 do not, with no error anywhere. Raw-mode children (which is most full-screen agent
  CLIs) are unaffected: 300KB arrives byte-perfect. This matters because an agent prompt easily
  exceeds 1KB and nothing reports the loss. Send such input to a cooked-mode child in chunks, or
  drive a raw-mode target.
- **A `--wait-for-regex` pattern that must span more than `MATCH_SPAN` characters is never
  found.** The pattern is matched against the most recent `MATCH_WINDOW_BYTES` of post-echo output;
  anything shorter than the re-read span is always found, whatever the turn grows to, but
  `OPEN[\s\S]*CLOSE` bracketing half a megabyte matched before this bound and does not now — such a
  send runs on to `--settle-ms` or `--timeout-ms` instead. Verified end to end at both sizes: 8 KB
  between the brackets matches, 512 KB does not. Wait for a marker, and use `read` for the span
  between two of them.
- **A reused `--wait-for-regex` pattern can match a reprint of an earlier answer.** `Echo#repaint?`
  vetoes a match covered by a copy of *this send's* input. It does not veto a match that is a
  reprint of *earlier output*. Measured on current main against a child that reprints its
  scrollback, sleeps 3s, then prints `DONE N`: send 1 with `'DONE \d+'` returned in 3.56s holding
  `DONE 1`; send 2 with the same pattern returned in 0.56s holding only the reprinted `DONE 1` —
  `DONE 2` was absent. Two candidate rules were considered and not shipped: rejecting a match
  whose text existed before the send loses a second `echo DONE` to a simple child; rejecting a
  match preceded by cursor-home / erase loses a TUI that paints a reused sentinel with cursor
  motion as the real new answer. Unique-per-turn sentinels wait through the reprint. A
  destination file the child writes is the other real check. `child_busy` is a `read` field
  and only means the child is still printing — it goes false during a silent think after the
  reprint, which is the measured case. Do not trust `matched` alone against a TUI that
  repaints scrollback.
- **The repaint veto needs to see a whole copy of the input, and a pty read can tear one in half.**
  `Echo#repaint?` rejects a match that a redrawn copy of the input covers, but it looks a bounded
  distance *after* the match as well as before, and that trailing half may not have arrived yet.
  Reproduced deterministically by splitting a repaint frame immediately after the token: whole
  frames are vetoed, the torn frame is not, and a pattern that appears only inside the caller's own
  input is answered `matched: true` by it. Pre-existing and unchanged by the match-window work;
  it is why a pattern that also occurs in what you sent remains the shape to avoid. Deferring such
  a match until its trailing context arrives is not obviously safe — an answer that is the last
  thing the child ever prints has no trailing context — so this is recorded rather than patched.
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
  as `busy_at_send: true`, and `--wait-for-regex` on a *per-turn* completion marker is still the
  right escape hatch for a child that redraws its input — but a reused pattern can match a reprint
  of an earlier answer, which is a different failure from the one that motivated the 3000 ms
  default, and is recorded under Known Limitations.
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
- **`--max-output=BYTES` bounds the transcript, not the reply.** The head and tail are joined by a
  `[rune] ==== N bytes omitted by --max-output ====` line, and pulling either cut back to an escape
  sequence boundary can drop a few more bytes; neither is charged against `BYTES`, so a reply can
  exceed it by roughly the marker's length. A caller sizing a buffer should allow for that. The
  budget has never been an exact ceiling in any case — `scrub` overshoots it whenever a cut splits a
  multi-byte character.
- **`clean_output` strips terminal control sequences but not terminal *semantics*.** With
  `TextSanitizer` widened (see the `parsers` change log) the escape codes are gone, but a
  full-screen agent's output is still a stream of repaints: the same line reappears many times and
  cursor-positioning is simply removed rather than replayed. It is readable, not a rendered screen.
  Reconstructing an actual screen would need a terminal emulator, which is out of scope.
- **`PromptScanner` duplicates the four-line last-line rule** that `PTYRunner#prompt_detected_in?`
  also implements. The honest shared home is `Parsers::PromptDetector`; extraction is deferred
  rather than done here so this change does not also rewrite the parsers contract.
- The in-memory transcript a supervisor keeps for cursor framing grows with session length.


### SPEC SECTION Change Log

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
| 2026-08-16 | CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and: Second review round: the regex echo bug fixed, four renderer defects fixed, and one rule disproved |
| 2026-08-17 | CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi: Make transcript cursors survive a mid-stream gap: record where each dropped region sits and map cursors through the list |
| 2026-08-17 | CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors: Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate |
| 2026-08-17 | CHG-0059-expose-subcommands-as-structured-data-in-per-command-help: Expose subcommands as structured data in per-command help |
| 2026-08-17 | CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus: Bound send output with --max-output and --tail, and make the two mutually exclusive |
| 2026-08-17 | CHG-0063-assert-the-geometry-rune-guarantees-not-the-scheduler-that-usually-delivers-it: Assert the geometry rune guarantees, not the scheduler that usually delivers it |
| 2026-08-18 | CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the: Stop a read mid-escape: withhold an unterminated sequence from the text and the cursor |
| 2026-08-18 | CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg: Make --tail count a carriage return as a line break, and report matched on a regex send's timeout |
| 2026-08-18 | CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun: Correct the flag message run gets wrong, and the five contracts the dogfood found documented wrong |
| 2026-08-18 | CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not: Guard the flags watch was executing, and bound the two fields max-output was not |
| 2026-08-18 | CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby: Make a failed launch loud, name the project a session is in, and fix two multibyte defects |
| 2026-08-18 | CHG-0072-snap-a-since-that-lands-inside-a-character-forward-instead-of-inventing-u-fff: Snap a --since that lands inside a character forward, instead of inventing U+FFFD |
| 2026-08-18 | CHG-0073-record-that-wait-for-regex-can-match-a-prior-turn-redraw-and-bring-the-1-0-ro: Record that --wait-for-regex can match a prior-turn redraw, and bring the 1.0 roadmap up to date |
| 2026-08-19 | CHG-0074-correct-the-wait-for-regex-reprint-advice-qualify-reprint-not-visible-histor: Correct the --wait-for-regex reprint advice: qualify reprint, not visible history, and stop pairing child_busy with the unique sentinel |
