# Persistent sessions (`rune session`)

`rune run` spawns a command, buffers everything, and returns once. `rune watch` streams a session
live but requires a real human terminal on stdin. Neither can hold a REPL-shaped child open across
separate `rune` calls — so an agent had no way to *start `codex`, send a prompt, wait for the
answer, send a follow-up.*

`rune session` adds that. A named session's child process outlives the `rune` invocation that
started it, and `send` blocks until the child has actually answered.

## Naming: every session has one, you rarely have to pick it

```console
$ rune session start -- grok
{"name":"grok-amber","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

Omit `--name` and rune generates an unused `<tool>-<word>` codename. That matters more than it
sounds: "the grok session" stops meaning anything the moment there are two, and an agent spinning
one up shouldn't have to invent identifiers. Pass `--name reviewer` when you want to choose.

Names are **scoped to a project** — the enclosing git working tree, or the directory itself outside
one. `reviewer` in one checkout and `reviewer` in another are different sessions, and neither is
reachable from the wrong directory:

```console
$ rune session list                  # this project only
$ rune session list --all-projects   # everything, labelled by project
```

## The loop

```console
$ rune session start --name grok -- grok
{"name":"grok","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

**`start` succeeding does not mean the child is running.** If the command does not exist, the
reply is still `status: "ok"` and `rune` still exits 0 — with `state: "exited"` and
`exit_code: 127` in the body. The start itself worked; the child died instantly. Check `state`,
not the process exit status.

`start` returns immediately and the `rune` process exits. `grok` keeps running, owned by a detached
supervisor that holds its pty.

```console
$ rune session send --name grok --settle-ms 2500 "reply with exactly the word PONG"
```

`send` writes the prompt, waits for grok to stop producing output for 2.5s, and returns **only what
that send produced**. State persists between calls, because it is the same child every time:

```console
$ rune session send --name s --settle-ms 300 "MEMORY=persisted"
$ rune session send --name s --settle-ms 300 'echo "value=$MEMORY"'
value=persisted
```

```console
$ rune session list
● grok-amber  running  idle 3s   grok
    Thought for 1s
● worker      running  idle 2m   bash --norc -i
    bash-3.2$

$ rune session stop --name grok-amber
```

Each row carries how long the session has been quiet and the last line it printed — which is the
fastest answer to *is this one working or stuck, and what is it doing?* when several agents are
running at once. The same fields (`idle_ms`, `last_line`) are in `--json`.

## Taking the wheel, and giving it back

```console
$ rune session attach --name grok-amber
[rune session] attached — Ctrl-] to detach (session keeps running)
```

`attach` connects your real terminal to a running session: output streams to your screen, your
keystrokes go to the agent, the current screen is replayed on connect so you don't stare at a blank
one, and **the child is resized to your terminal** (and follows it as you resize) so a full-screen
agent lays out for your window rather than the headless default. When you detach, the child returns
to that default, so programmatic `send`s render the same whether or not you attached. **Ctrl-]** detaches and leaves everything running — that is the whole difference from
`rune watch`, which owns the child it spawned. Ctrl-C is deliberately *not* the detach key: it has
to keep reaching the child so you can interrupt a runaway agent.

## Archiving

A stopped session keeps its name reserved and clutters `list`. Archive it:

```console
$ rune session stop --name reviewer
$ rune session archive --name reviewer
$ rune session list --archived
```

Archiving frees the name and files the transcript under the project's archive. An archived session is out of
`read`'s reach — `read --name` on it reports no such session — so pull anything you still want
*before* archiving. An archived session
can never be mistaken for a live one, and reusing the name starts genuinely fresh — `start` resets
the transcript so `send` cursors and `read` offsets always describe the same lifetime.

## Knowing when the other agent is done

This is the hard part, and rune gives you three tools in order of preference.

**`--settle-ms N` (default 800)** — return once the child has been quiet for N ms. This is the
primary signal. The settle clock only starts once output arrives that isn't the pty's echo of your
own input, so an agent that echoes your prompt and then thinks before answering returns the answer
rather than your words back.

> **Known limitation, and the sharpest one in rune today: a child that *redraws* your input can
> still settle on it.** The rule above holds when the echo arrives once. A line editor that repaints
> the line on submit sends your input a second time, and that second copy counts as the child having
> spoken. Measured with `--settle-ms 800`: `irb` and `python3 -q` return `settled: true` in about a
> second with only the echo, 3 times out of 3 each, while the real answer arrives seconds later and
> lands in whatever the *next* call captures. Plain `bash -i` is unaffected, including inputs that
> wrap past the terminal width.
>
> **Nothing in the reply distinguishes this from a real answer** — `settled: true`,
> `busy_at_send: false`, and the echo is legitimately part of a correct reply too. Until it is
> fixed, drive a repainting REPL with `--wait-for-regex`, which is not affected, or check that the
> reply contains something beyond what you sent.

**`--wait-for-regex RE`** — return as soon as output matches. Deterministic, and the right answer
whenever you know what the callee prints when it's done:

```console
$ rune session send --name s --wait-for-regex '\$ $' "ls"
```

> **The pattern is matched against the reply, not against the echo of your input.** A pty echoes
> what you write, so a naive implementation returns the instant your own words come back. rune
> locates the echo in *condensed* text — escapes and whitespace removed from both sides, which is
> the difference between what you sent and every transformed echo we could capture — and vetoes a
> match that a repainted copy of the input covers. Measured against `python3 -q`, whose REPL
> repaints per keystroke: previously it returned in 0.22s with `matched: true`, eight seconds before
> the code ran, 4 times out of 4; it now waits for the real output, 3 times out of 3.
>
> The honest claim is *every echo shape we could capture from a real child is excluded*, not
> *cannot happen*. If your pattern is a literal you also sent, a child that quotes your request back
> verbatim can still satisfy it. The veto also needs to *see* the copy: a repaint that a pty read
> tore in half — the frame ends mid-redraw and the rest arrives in the next read — is not yet
> recognisable as a copy, and a pattern that only appears inside your own input can be satisfied by
> that half. Reproduced deterministically by splitting a frame immediately after the token. So a
> pattern that also occurs in what you sent is still the shape to avoid.

> **How much output the pattern is matched against: the most recent 256 KB past the echo, re-read
> 32768 characters back on every read.** This is a deliberate bound with two consequences.
>
> - **A single match up to 32768 characters long is always found**, however large the turn grows,
>   because each scan resumes that far behind where the last one stopped. Anything you would
>   sensibly wait for — a marker, a prompt, a closing fence — is far inside that.
> - **A single match that has to span more than 32768 characters is never found.**
>   `OPEN[\s\S]*CLOSE` across half a megabyte used to match and now does not; the send runs on to
>   `--settle-ms` or `--timeout-ms` instead. Wait for `CLOSE` on its own and use `read` if you need
>   the span between them.
>
> `\A` still anchors to the start of the child's answer, not to the start of the window — an
> anchored pattern cannot be satisfied by wherever the window happens to begin. `^`, `$` and `\z`
> are unaffected. **The reply is not bounded by any of this:** `output` is still everything the
> child produced for the turn.
>
> The bound is what makes a large answer reachable at all. The pattern used to be matched against
> the whole turn on every 4 KB read, which is quadratic in the turn — and on the supervisor's only
> thread, so it starved the pty drain as well. Measured against a child that emits N MB and then
> prints a marker, with the same marker as the pattern:
>
> | output | before | after |
> | --- | --- | --- |
> | 4 MB | 11.85s, matched | 0.53s, matched |
> | 12 MB | 90.51s, `timed_out: true`, 11.46 MB of 12.00 read | 0.98s, matched, 12.15 MB read |
> | 48 MB | 112.43s, matched | 3.37s, matched |
>
> At 12 MB the send reported a timeout while holding 96% of an answer whose marker the child had
> already printed.

**`--timeout-ms N` (default 120000)** — a hard cap. On expiry you get what was captured plus
`settled: false, timed_out: true` — a result, not a failure. Set this deliberately: the default is
generous because agents are slow, so a mistaken call costs two minutes.

`--no-wait` writes and returns immediately, for when you don't expect a reply at all. Its reply is a
different shape — `{action, name, sent: true, waited: false}`, with no `output`, `cursor` or
`prompt_detected`, because nothing was waited for.

`--no-newline` writes the text without the trailing carriage return that submits it, for composing a
line in pieces or driving a TUI that reads keystrokes.

### The other fields on a reply

- `settled: true` — the child went quiet for the settle window. The normal success, but quiet has
  three causes and this cannot tell them apart: the turn finished, the child is waiting on a human,
  or **the child backgrounded a long command and stopped printing**. That third case is the one that
  bites: a caller polling for the disappearance of a busy marker read a frame without it and
  concluded the work was done, 260 seconds before it was. If you are deciding on the *absence* of
  something, `settled` is not enough evidence on its own.
- `timed_out: true` — `--timeout-ms` was reached first. A result, not a failure.
- `matched: true` — `--wait-for-regex` matched.
- `child_exited: true` — the child ended while the send was in flight.
- `busy_at_send: true` — the child was *still producing output* when this send landed, so the reply
  may contain the tail of the previous turn. Worth checking if an answer looks like it belongs to
  the previous question.
- `regex_timed_out: true` — the `--wait-for-regex` pattern exceeded its match budget and was
  abandoned. Almost always a catastrophically backtracking pattern; simplify it.
- `dropped_bytes` — a count of earlier output rotated away before this read. It does **not**
  invalidate a `--since` cursor: cursors stay absolute, so one from before the rotation returns
  everything still held rather than an error.

### `child_busy` and `idle_ms` are on `read`, not on `send`

Whether the child has printed anything within the settle window, and how long since it last did.
This is the structured form of "is it still working": use it rather than grepping the callee's own
UI for a busy marker, which is presentation and changes without notice.

**They are fields of `read` and `list`, not of a `send` reply.** A `send` already blocked until the
child settled, so ask afterwards:

```console
$ rune session send --name grok --settle-ms 2500 "run the suite"
$ rune session read --name grok --tail 1 --json     # child_busy, idle_ms
```

This document previously listed both among a `send` reply's fields, which is wrong in the way that
matters most — a caller who reads `.child_busy` off a `send` gets `nil`, and falls back to grepping
the UI, which is the exact thing these fields exist to replace.

Note the name says the child is *printing*, not that it is *working*: a child that backgrounded a
command and went quiet reports `child_busy: false`.

### Finding something in a long transcript

`--since` and `--tail` do not help when what you want is in the middle. A day's work with a driven
agent reached 379KB.

```console
$ rune session read --name grok --grep 'THE BOARD' --context 2
```

It matches the *cleaned* text rather than the raw stream, because a full-screen agent's repaint
frames split words across escape sequences — a pattern you can plainly see on screen will not match
the bytes. The reply carries `grep_matches`, and an unparseable pattern comes back as `grep_error`
rather than an exception.

### `prompt_detected` is advisory only

Every `send`/`read` result carries `prompt_detected`, but **do not gate on it**, and know which way it fails.

Measured against real output: it is `false` for plain text, `false` for a bare `$ `, **`false` for
`Do you want to proceed?`**, and `true` for `❯ `. So for grok it is `true` on essentially every read,
because grok's composer always ends in `❯` — one caller saw it `true` 8 times out of 8 and concluded
it discriminated nothing. It does discriminate; it is simply detecting *prompt-shaped last lines*,
which is not the same question as "is this waiting for me". Note the third case above: it is `false`
for exactly the permission dialog you would most want it to catch. Look at the screen for that. rune's prompt
patterns match shell-shaped prompts (`user@host:~$`, `[y/N]`, `Password:`) and are deliberately
conservative. Agent REPLs mostly look like none of those, so for exactly the CLIs you want to drive
it is usually `false`. Waiting for a prompt would hang against most real targets — that's why
settle-time is the primary signal.

## Reading the transcript

`read` replays the session's durable transcript, and works the same whether the session is live or
already stopped:

```console
$ rune session read --name grok --tail 50
$ rune session read --name grok --since 41234     # page from a cursor a previous call returned
```

Every session writes an NDJSON event log in the same format `rune watch` produces, so you can
follow a live session from another pane:

```console
$ tail -f ~/.rune/projects/<project>/sessions/grok/output.ndjson
```

Full-screen TUI agents generate a lot of ANSI repaint traffic, so prefer `--tail`/`--max-output`
over reading a whole transcript.

### `--screen`: what the terminal shows, not what arrived

For a full-screen agent this is usually the field you want. The byte stream contains every frame of
every repaint, with the answer split across them; the screen contains only what is displayed.

```console
$ rune session send --name grok --screen -- "reply with just the branch name"
$ rune session read --name grok --screen
```

Measured against grok: a 361KB transcript rendered to a 1.1KB screen, and an answer the agent had
plainly displayed was **absent from the byte stream in 3 of 3 turns and present in the rendered
screen in 3 of 3**. If you are matching on content, match on `screen`.

Two things it is not. It is the *end state*, so anything scrolled away is gone — the transcript
remains the record of what happened. And it is opt-in because it is only meaningful for a child that
paints a screen: for a cooked-mode shell the byte stream already is the answer.

**It is rendered from the last 256KB, and for some agents that has a visible cost.** A census of
grok's output over 4.5MB found 109,364 absolute cursor moves, 31,798 synchronised-update brackets,
and **zero** erases of any kind — no `\e[K`, no `\e[2K`, no `\e[2J`, no scroll regions. An agent
that repaints purely by positioning and overwriting depends on the terminal remembering every cell
it wrote, however long ago. Rendering from a window starts from a blank grid instead, so anything
painted once and never repainted — a header, a banner — is simply absent, and rune cannot tell that
it is missing. Reading `--screen` more often does not help; the window is measured in bytes, not
time.

The same census explains a subtler point. When an agent never erases, a duplicated line on screen
may be entirely faithful: if its layout shifts down a row and it repaints at the new position, the
old copy has nothing to remove it, and **a real terminal shows the duplicate too**. Before treating
a repeated line as a rune bug, check whether the agent erases anything at all.

### Known limitation: a polled `--screen` can return a half-painted frame

Reported from real use, and **not fixed**. Polling `--screen` on a repainting agent occasionally
returns a frame that is mid-repaint — in the reported case, a line duplicated on two adjacent rows.

Two candidate fixes were measured and rejected. Comparing consecutive renders and returning only a
repeated one measured **worse** than doing nothing — 13 torn frames out of 20 against 11 — because
an agent painting on a cycle rarely renders the same frame twice, so the check times out and hands
back the torn frame regardless. Redefining stability as quiescence could not reproduce the tear at
all: the identical child gave 11/20 once and 0/20 twice, which means the harness was not measuring
what it appeared to. A fix that fails silently toward "looks done" is worse than a limitation you
can plan around.

**What to do about it.** Do not treat one rendered frame as authoritative for a decision you cannot
undo. If you are reading a value, poll twice and require agreement. If you are waiting for a marker,
`--wait-for-regex` is deterministic where `--screen` is a snapshot.

**It may not be rune's fault.** A census of one agent's output over 4.5MB found zero erases of any
kind, and an agent that never erases and shifts its layout leaves the old copy on screen — a real
terminal shows the duplicate too. rune's renderer agrees with an independent emulator across six
profiles built from that census. Before filing a duplicated line as a rune bug, check whether the
agent erases anything at all.

### The transcript is bounded

Both the file and the supervisor's memory are capped, so a session left running for a day does not
grow without limit. When rotation drops older output, `read` reports `dropped_bytes` and cursors
stay absolute — a cursor still names the same position in the stream, it just points at output no
longer held.

## What to know before driving a real agent

- **`start` returns when the *supervisor* is ready, not the child.** An agent CLI takes seconds to
  boot, and input sent before it is listening is simply lost. Wait for a readiness marker — poll
  `read`, or make the first `send` a `--wait-for-regex` — before driving a freshly started session.
- **Settle is a heuristic.** A child that pauses mid-answer for longer than `--settle-ms` returns a
  truncated response. Raise it, or use `--wait-for-regex`.
- **`--wait-for-regex` sees the most recent 256 KB, not the whole turn.** Any one match up to 32768
  characters long is always found; a match that has to span more than that never is. Wait for a
  marker, not for a pattern that brackets megabytes.
- **A single line of 1024+ bytes vanishes into a cooked-mode child.** That is `MAX_CANON`, a
  terminal limit, not rune's: the line discipline cannot assemble a longer canonical line and drops
  it silently — 1023 bytes arrive, 1024 do not. Most agent CLIs run their terminal in raw mode and
  are unaffected (300KB arrives byte-perfect). So does an interactive shell: `bash --norc -i` uses
  readline, which puts the terminal in raw mode, and takes a 1995-character line byte-perfect. The
  limit bites a child that reads in *cooked* mode — a bare `cat`, or a script reading stdin without
  readline. Chunk it, or drive a raw-mode target.
- Enter is sent as a carriage return, which is what a real terminal sends, so raw-mode TUIs receive
  it. Cooked-mode shells are unaffected.
- The child's pty gets an explicit window size, because a detached session has no terminal to copy
  one from and an unset pty is 0x0 — which leaves full-screen agents rendering into nothing.

## Where state lives

`RUNE_HOME` (default `~/.rune`), with owner-only permissions:

```
$RUNE_HOME/projects/<project>/
  sessions/<name>/
    meta.json        0600   pid, supervisor pid, command, state
    output.ndjson    0600   full transcript
    supervisor.log   0600   supervisor stderr, for when something goes wrong
    control.sock     0600   the supervisor's control socket
  archive/<stamp>-<name>/   archived sessions, out of the live namespace
```

Set `RUNE_HOME` to keep sessions isolated (tests, sandboxes, parallel work).

## What running many at once costs

One session is one supervisor process, and that isolation is deliberate: a wedged agent takes down
its own session and nothing else. The price is a Ruby interpreter per session, and it is worth
knowing before you fan out.

Measured, with idle children:

| sessions | resident memory | descriptors |
|----------|-----------------|-------------|
| 24 | 543 MB | 648 |
| 60 | 1361 MB | 1620 |

That is **~23 MB and 27 descriptors per session**, flat — the same at 60 as at 24, and unchanged
across rounds of sends. So the cost is predictable and linear rather than surprising, but it is
front-loaded: sixty agents cost well over a gigabyte before any of them has done anything.

Concurrency itself held up under the same test: 60 simultaneous starts all succeeded, every send
reached the session it was addressed to, `list` agreed with reality, and nothing was left running
afterwards. Thirty simultaneous `start` calls *without* `--name` for the same tool produced thirty
distinct codenames and no collisions.

## Scope

rune is a session **broker**, not a message bus. It holds sessions and addresses them by name;
deciding who talks to whom is the calling agent's job — it already has the names. Cross-session
routing, per-agent profiles, and a shared conversation log are deliberately out of scope.
