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

### `prompt_detected` is advisory only

Every `send`/`read` result carries `prompt_detected`, but **do not gate on it**. rune's prompt
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

## Scope

rune is a session **broker**, not a message bus. It holds sessions and addresses them by name;
deciding who talks to whom is the calling agent's job — it already has the names. Cross-session
routing, per-agent profiles, and a shared conversation log are deliberately out of scope.
