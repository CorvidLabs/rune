---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: design
---

# Design

## The gap this closes

rune has two execution models today and **both die with the `rune` process**:

| | `rune run` (`PTYRunner`) | `rune watch` (`PTYWatcher`) |
|---|---|---|
| Shape | spawn, buffer everything, return once | live bidirectional passthrough |
| Driver | any caller | **a human only** — hard-fails `unless @input.tty?` |
| Lifetime | one invocation | one invocation |

Neither supports the actual use case: *start `codex`, send it a prompt, wait for it to finish
answering, read the answer, send a follow-up.* `run` can't hold a REPL open; `watch` can hold one
open but refuses to run without a human terminal and streams to a screen rather than returning
data. An agent driving another agent has no path.

Two new primitives close it:

1. **Persistent named sessions** — the PTY child outlives a single `rune` invocation.
2. **Send-and-settle** — send input, block until the child goes quiet, return exactly the output
   that send produced. This converts an async TTY into a synchronous request/response call.

(2) is the half that makes it usable. Every agent REPL has the same shape — you type, it streams,
it goes quiet — so a generic settle primitive drives all of them without per-vendor knowledge.

## Decision 1: per-session detached supervisor, stdlib only

A PTY master fd lives in a process. If `rune session start` spawns and exits, someone must still
hold it. Three options were considered:

| Option | Verdict |
|---|---|
| **Per-session detached supervisor** | **Chosen.** Zero new runtime deps, fits rune's stdlib-only identity, reuses the existing NDJSON event-log format, debuggable with `tail -f`. Cost: we own daemon-lifecycle edges (orphans, stale state). |
| tmux-backed | Rejected. Far less code and battle-tested, but a hard external dependency against rune's zero-dep stance, and `capture-pane` yields a *rendered screen*, not the byte stream — losing output fidelity and making the existing ANSI/UTF-8 machinery irrelevant. Viable later as an optional backend. |
| Central `runed` daemon | Rejected for v1. Cleanest multiplexing, but full daemon lifecycle (start/stop/upgrade/crash recovery) and the biggest departure from "a CLI you just run". |

`rune session start` re-invokes rune's own executable as a hidden `session _supervise` subcommand
via `Process.spawn` with `pgroup: true`, stdio redirected to `/dev/null`. The supervisor calls
`Process.setsid` (rescued) at startup so it survives the launching terminal closing, then
`PTY.spawn`s the target and owns the master fd for the session's life.

## Decision 2: Unix socket control channel, not a FIFO

The first sketch used a FIFO for input. Rejected: FIFO semantics are hostile here — a reader gets
EOF whenever the last writer closes, so the supervisor must continually reopen it, and there is no
way to return a *reply* to the caller.

A `UNIXServer` (stdlib `socket`) at `control.sock` is strictly better, and it is what makes
send-and-settle correct rather than approximate: **the supervisor owns the output stream, so it
knows exactly when new bytes arrive.** The client sends one JSON request line and blocks for one
JSON reply line. Settle detection therefore happens where the data is, instead of the client
tailing a file and guessing.

    {"op":"send","text":"...","settle_ms":800,"timeout_ms":120000}
 -> {"output":"...","prompt_detected":true,"settled":true,"cursor":41234}

Ops: `send`, `read`, `status`, `stop`. A single-threaded accept loop serializes concurrent clients
for free. Unix-only, consistent with rune already requiring PTY.

`output.ndjson` is still written as the durable transcript in the **exact event format
`PTYWatcher#log_event` already emits**, so `tail -f` debugging and post-hoc reads work, and the
format stays one thing rather than two.

## Decision 3: settle-time is primary; `prompt_detected` is advisory only

`PromptDetector::PROMPT_PATTERNS` is tuned for *shell* prompts (`user@host:~$`, `[y/N]`,
`Password:`, `➜`) and is deliberately conservative — its own comment says "prefer a rare false
negative over a false positive."

Agent REPLs mostly do not look like that. **`prompt_detected` will frequently be `false` for
exactly the CLIs this feature exists to drive**, so it must not be the primary "is it done"
signal. Ordering:

1. `--settle-ms N` (primary) — return once no new output for N ms.
2. `--wait-for-regex RE` (precise escape hatch) — return as soon as output matches.
3. `--timeout-ms M` (hard cap) — return what we have with `settled: false, timed_out: true`.
4. `prompt_detected` — reported as metadata, never gates the return.

Send takes the output cursor **at send time** and returns only bytes after it, so a banner printed
before the send is never misattributed to the response.

This is a heuristic and the spec says so plainly: an agent that pauses mid-answer longer than
`--settle-ms` returns a truncated response. `--wait-for-regex` is the deterministic answer when the
callee's prompt is known.

## Reuse (this is an addition, not a parallel stack)

- `UTF8StreamDecoder` — incremental decode across chunk boundaries.
- `PromptDetector` + `TextSanitizer.strip_ansi` directly.
- The last-non-blank-line rule from CHG-0024 is currently private inside
  `PTYRunner#prompt_detected_in?`. Sessions need identical semantics, and the intent was to extract
  it to one shared home. **Deferred deliberately:** the honest place for a generic text rule is
  `Parsers::PromptDetector`, which would pull the `parsers` spec (and a `pty_runner` edit) into a
  change that is already large, and putting it under `Session::` while `PTYRunner` reaches into it
  would be worse layering than the duplication it removes. So `Session::PromptScanner` carries its
  own copy of the four-line rule for now, with the shared-home extraction left as a follow-up.
  Recorded here rather than silently duplicated.
- `PTYWatcher`'s NDJSON event vocabulary (`start`/`output`/`exit` + `ts`).
- `OutputLimiter` for `--tail`/`--max-output` on `read`.
- `Result` / `Renderer` / the `Command` `usage`/`flag` DSL for the CLI surface.

## State layout

`RUNE_HOME` (default `~/.rune`) — rune's first env var and first persisted state.

    $RUNE_HOME/sessions/<name>/     0700
      meta.json                     0600  pid, supervisor_pid, command, started_at, state
      output.ndjson                 0600  full transcript, PTYWatcher event format
      control.sock                  0600  supervisor's UNIXServer

Follows the existing security precedent set for watch logs (owner-only, collision-safe,
symlink-resistant).

## Known risks, stated up front

1. **Lifecycle is where the bugs will be** — orphaned children, supervisors that die without
   cleanup, stale `meta.json`. `list` must therefore verify liveness (`Process.kill(0, pid)`)
   rather than trust `meta.json`, and report `dead` distinctly from `running`.
2. **Testing detached processes is genuinely harder** than the in-process PTY tests. Every spec
   runs against a temp `RUNE_HOME` and must reap in an `ensure`/`after` hook; a leaked supervisor
   in CI is the failure mode to design against from the start.
3. **Settle detection is heuristic** (see Decision 3) — documented, not hidden.
4. **Concurrent sends** to one session are serialized by the single-threaded accept loop.
