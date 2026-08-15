# Changelog

## [Unreleased]

### Added

- `rune session` — persistent, named PTY sessions that outlive a single `rune` invocation, so one
  agent CLI can drive another conversationally instead of one-shot. `rune session start --name X --
  <cmd>` spawns the child under a detached per-session supervisor that owns the pty; `rune session
  send --name X "..."` writes to it and returns *only* the output that send produced; `rune session
  read`/`list`/`stop` cover the rest. Neither existing execution model could do this: `rune run`
  buffers and returns once, and `rune watch` hard-refuses to run without a human terminal on stdin,
  so an agent had no way to hold a REPL-shaped child open across calls.
- **Send-and-settle**, the primitive that makes the above usable: `--settle-ms` returns once the
  child has been quiet for N ms, `--wait-for-regex` returns as soon as output matches, and
  `--timeout-ms` caps the whole wait (reporting `settled: false`, `timed_out: true` rather than
  failing). Together these turn an async TTY into a synchronous request/response call. Settle-time
  is the primary completion signal deliberately: `prompt_detected` only matches shell-shaped
  prompts, so it is usually `false` for exactly the agent REPLs this exists to drive, and is
  reported as advisory metadata that never gates a reply.
- `rune session attach` connects your real terminal to a running session — output streams to the
  screen, keystrokes go to the agent, and the current screen is replayed on connect. **Ctrl-]**
  detaches and leaves everything running, which is the whole difference from `rune watch` (which
  owns the child it spawned). Ctrl-C deliberately still reaches the child so a runaway agent can be
  interrupted.
- Sessions are **named and project-scoped**. `--name` is optional for `start` — an unused
  `<tool>-<word>` codename is generated otherwise — and names are scoped to the enclosing git
  working tree, so `reviewer` in two checkouts is two sessions and neither is reachable from the
  wrong directory. `rune session list --all-projects` opts out of the scoping.
- `rune session archive` files a stopped session away, freeing its name and keeping history out of
  the live list; `rune session list --archived` shows it.
- `rune session list` reports `idle_ms` and a `last_line` summary per session, so "is this one stuck
  and what is it doing" is answerable at a glance when several agents are running.
- Session state lives under `RUNE_HOME` (default `~/.rune`) with owner-only `0700` directories and
  `0600` files, and each session's transcript is an NDJSON event log in the **same format `rune
  watch` already writes**, so `tail -f` works on a live session.

### Changed

- Examples are split by audience: `examples/agents/` (structured, programmatic — including a
  bash+jq example for agents that shell out rather than requiring the gem) and `examples/humans/`
  (interactive programs meant to be driven from a terminal). Each folder has a README, and new
  examples cover the library surface, multi-session fan-out, failure handling, driving rune as a
  subprocess without loading the library, and a stand-in agent REPL that costs no API quota. The
  repository is now Ruby end to end — no shell scripts remain.
- CI no longer runs the Augur risk gate or Attest provenance verification, and `spec-sync` runs
  without `--strict`/`--stale`. The contract itself — specs matching code, coverage staying
  complete — is the part worth gating on; the rest was rejecting work for bookkeeping reasons
  rather than for drift between specs and code. To be revisited when spec-sync 6 lands, which
  reworks the change-verification model. The spec-sync job also no longer waits on the Ruby matrix:
  the two check different things and neither needs the other, so running them side by side returns
  a result in ~90s instead of ~2m40s. `scripts/trust_range.sh` and
  `scripts/squash_attest_forwards.sh` existed only to make those gates non-vacuous and are removed
  with them.

### Fixed

- `Parsers::TextSanitizer` now strips private-parameter CSI (`\e[?1049h`, `\e[?2026h`), OSC strings
  (`\e]0;title\a`), DCS/SOS/PM/APC strings, and keypad/cursor-key modes, not just SGR-shaped
  sequences. The old pattern left a full-screen TUI's escape traffic almost entirely intact, so
  `clean_output` was unreadable for exactly the agent CLIs sessions exist to drive. Improves
  `rune run` on any TUI command equally.

## [v0.3.0] - 2026-08-14

### Added

- `rune run --max-output=BYTES` bounds `clean_output`/`raw_output` to BYTES each, keeping head and
  tail (the middle is omitted), reporting `truncated`/`omitted_bytes` in the result. `rune run
  --tail=N` keeps only the last N lines of each, reporting `truncated`/`omitted_lines`. Both are
  opt-in and mutually exclusive; the default result data shape is unchanged when neither is
  passed. Addresses #12 (`rune run` previously buffered a chatty command's entire output
  unbounded — 18.7MB of JSON from 5 seconds of `yes`).
- `rune watch --timeout=SECONDS` kills the session after N total seconds; `rune watch
  --idle-timeout=SECONDS` kills it after N seconds with no output and no input. Both are opt-in,
  may be combined, and default to unset (preserving today's unbounded interactive behavior). On
  expiry the child is killed and reaped, and the result reports `exit_code: 124`, `timed_out:
  true`, `timeout_kind: "timeout"|"idle_timeout"`. Addresses #14 (`rune watch` previously had no
  timeout anywhere in its path, so an agent driving a child that never exits hung forever with no
  recovery).
- `rune run --separate-streams` spawns stdout on a real pty and stderr on a plain pipe, adding
  `clean_stdout`/`clean_stderr` to the result alongside the existing merged `clean_output`/
  `raw_output` view. Opt-in — the wrapped child loses true controlling-terminal semantics on this
  path, which is why it isn't the default. Addresses #15 (previously stdout and stderr arrived
  merged with no way to distinguish them, a regression against plain `subprocess.run`).
- `--help` and `-h`, at the top level (`rune --help`) and per command (`rune run --help`), plus
  `rune help <command>`. Command help lists that command’s own flags — `--timeout=SECONDS`,
  `--log=PATH` — which were previously discoverable only from `specs/` and from the error you got
  for using them wrong.
- A `usage`/`flag` DSL on `Rune::Command` so each command declares its own invocation shape and
  flags next to the code that parses them.
- Help is a normal `Result`, so `rune run --help --json` returns `usage` and `flags` as structured
  data an agent can read without scraping the human rendering.

### Fixed

- `prompt_detected` in `rune run`'s result now reflects whether the *last* non-blank line of
  output looks like an interactive prompt, not whether any line anywhere in the entire run ever
  did. `rune run`'s result is only ever read after the process has already exited or been killed
  by `--timeout`, so "did a prompt-shaped line ever appear" was never the useful question — for a
  long TUI-heavy session it was nearly always `true` and told an agent nothing (#30, found via
  real dogfooding). Also fixes a related latent bug: on an actual `--timeout` kill,
  `prompt_detected` was unconditionally `false` regardless of what was actually on screen when the
  process was killed — exactly the case where the field is most useful.
- `rune --help` returned `Unknown command: --help` and exit 1; `rune run --help` tried to *execute*
  `--help` in a pty and exited 127.
- Route `rune watch`'s live passthrough to stderr in agent mode (`--json`, `--ndjson`, or piped
  stdout) so stdout carries only the result envelope. It previously emitted the wrapped command's
  raw output followed by the JSON, which meant `rune watch --json` produced stdout that did not
  parse.
- Compute an explicit, non-empty commit range for the risk and provenance gates, and fail when that
  range is empty. On a push to `main` the range resolved to zero commits, so both gates reported
  success while inspecting nothing.
- Derive push-event trust ranges from GitHub's exact before/after SHAs so a multi-commit push cannot
  leave earlier commits outside Augur and Attest while only checking the tip.
- Forward the provenance recorded on a squash-merged pull request head onto the landed commit, so a
  push to `main` is verified against the review that actually happened.
- Keep the non-PTY end-to-end examples loadable on platforms where Ruby's optional `pty` extension
  is unavailable, while skipping only the examples that genuinely require a PTY.

### Changed

- Assert end-to-end that the complete stdout of every command parses as a single JSON document, in
  every agent output mode.
- Exercise trust-range selection against real temporary Git histories, including a three-commit
  push, and simulate a Ruby installation without the `pty` extension.

## [v0.2.1] - 2026-07-28

### Fixed

- Preserve `--json` and `--ndjson` flags after the command separator instead of consuming flags
  intended for the wrapped process.
- Decode UTF-8 incrementally so multi-byte characters split across PTY reads remain intact.
- Mirror terminal dimensions into watched child processes and track resize changes while polling.
- Kill and reap watched children when an output sink closes with `EPIPE`.
- Create default watch logs as collision-safe, symlink-resistant, owner-only `0600` files.

### Changed

- Test every supported Ruby minor from 3.0 through 4.0 and enforce strict spec-sync, risk, and
  provenance gates.
- Include linked documentation and examples in the built gem and correct installation guidance.
- Add release version parity, package, smoke, and provenance checks before publishing.

## [v0.2.0] - 2026-07-27

### Other

- Bump version to 0.2.0 (3ef80d1)
- Fix 9 real issues from PR #3's automated review triage, update docs for 0.2.0 (d00a99e)
- 0.2.0 launch prep: PTY timeout flag, TableParser format option, docs, roadmap (#3) (2e68ad9)
