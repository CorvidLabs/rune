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
{"action":"start","name":"grok-amber","state":"running"}
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
{"action":"start","name":"grok","child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

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

Archiving frees the name and files the transcript under the project's archive. An archived session
can never be mistaken for a live one, and reusing the name starts genuinely fresh — `start` resets
the transcript so `send` cursors and `read` offsets always describe the same lifetime.

## Knowing when the other agent is done

This is the hard part, and rune gives you three tools in order of preference.

**`--settle-ms N` (default 800)** — return once the child has been quiet for N ms. This is the
primary signal. The settle clock only starts once output arrives that *isn't* the pty's echo of
your own input, so an agent that echoes your prompt and then thinks for five seconds before
answering still returns the answer, not your words back.

**`--wait-for-regex RE`** — return as soon as output matches. Deterministic, and the right answer
whenever you know what the callee prints when it's done:

```console
$ rune session send --name s --wait-for-regex '\$ $' "ls"
```

**`--timeout-ms N` (default 120000)** — a hard cap. On expiry you get what was captured plus
`settled: false, timed_out: true` — a result, not a failure. Set this deliberately: the default is
generous because agents are slow, so a mistaken call costs two minutes.

`--no-wait` writes and returns immediately, for when you don't expect a reply at all.

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
- `child_busy` / `idle_ms` — whether the child has printed anything within the settle window, and
  how long since it last did. This is the structured form of "is it still working": read it rather
  than grepping the callee's own UI for a busy marker, which is presentation and changes without
  notice. Note it says the child is *printing*, not that it is *working* — a child that backgrounded
  a command and went quiet reports `child_busy: false`.
- `dropped_bytes` — a count of earlier output rotated away before this read. It does **not**
  invalidate a `--since` cursor: cursors stay absolute, so one from before the rotation returns
  everything still held rather than an error.

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
- **A single line of 1024+ bytes vanishes into a cooked-mode child.** That is `MAX_CANON`, a
  terminal limit, not rune's: the line discipline cannot assemble a longer canonical line and drops
  it silently — 1023 bytes arrive, 1024 do not. Most agent CLIs run their terminal in raw mode and
  are unaffected (300KB arrives byte-perfect), but a shell-like child will simply never see a long
  prompt. Chunk it, or drive a raw-mode target.
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
