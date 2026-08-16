# Changelog

## [Unreleased]

### Fixed

- **The screen tail could cut an escape sequence in half and print its remainder onto the screen.**
  Found from a census of a real agent's output: 109,364 absolute cursor moves and 31,798
  synchronised-update brackets across 4.5MB, and **zero** erases of any kind. A stream that is
  almost entirely escape sequences makes the render window's cut far likelier to land inside one
  than in text, and the remainder has no `ESC` left to identify it — cutting inside `\e[?2026h` put
  a literal `?2026h` on screen. The code carried a comment claiming this was harmless. The cut now
  resyncs to the first escape, bounded so that a stream with no escapes keeps its text.
- **Three releases in a row failed to publish and nobody noticed.** v0.4.0, v0.5.0 and v0.6.0 each
  failed at the provenance check inside `Publish Gem Package` — after the tag existed and the
  release was announced — because the documented step that records provenance was skipped. Nothing
  downstream broke, which is exactly why it went unseen: the Homebrew formula builds from the tag
  tarball and the rubygems.org job is disabled, so the only casualty was a package nobody installs.
  The release lane now runs `provenance-check` up front, so a missing attestation stops a release
  before the tag rather than after it, and says what to run to fix it.

## [v0.7.0] - 2026-08-15

Everything here comes from one day of field use: an agent drove grok through rune to do real work on
another repository — eight one-shot dispatches and a live session — and reported back with
measurements rather than opinions. Two of its five findings turned out to be right about the symptom
and wrong about the cause, which is why one of them appears below as a documentation fix rather than
a code change, and why the most important one is deliberately still open.

### Added

- **`read --grep=RE --context=N`.** Finding one line in a 379KB transcript otherwise means pulling
  most of it into the caller's context, and neither `--since` nor `--tail` helps when what you want
  is in the middle. It matches the **cleaned** text rather than the raw stream, because a
  full-screen agent's repaint frames split words across escape sequences — a pattern plainly visible
  on screen does not match the bytes, which would make the feature look broken exactly where it is
  needed. `grep_matches` comes back in the reply; an unparseable pattern returns `grep_error`
  instead of raising, since a caller's typo is not a reason to fail a read.
- **`child_busy` and `idle_ms` on `read`.** The reporter had no structured way to ask whether the
  child was still working, so was grepping the callee's own rendered UI for `command still running`.
  That is presentation, not API, and it breaks the first time the wording changes. Both fields are
  derived from the transcript's own event timestamps rather than asked of the supervisor — the same
  source `list` already uses, so they work identically once a session has stopped. Measured:
  `child_busy=true, idle_ms=61` while printing; `child_busy=false, idle_ms=3268` after finishing.
  The field is named for what it observes, and the case it cannot see — a child that backgrounds a
  command and goes quiet reports `child_busy: false` while still working — is stated next to it
  rather than left to be discovered.

### Documentation

- **`prompt_detected` was described as usually false for agent CLIs.** It is not, and a caller had
  already built on the claim, which is worse than no documentation at all. Measured: `plain output`
  false, `$ ` false, `Do you want to proceed? ` **false**, `❯ ` **true**. So the report of "true 8
  times out of 8" was correct for that callee, and the conclusion that the field discriminates
  nothing was not — it discriminates, but answers "does the last line look like a prompt", and
  answers it backwards for the permission dialog, which is the case worth catching. Documented with
  that table.
- **`settled` has three causes of quiet, not two.** The turn finished, the child is waiting on a
  human, or the child backgrounded a long command and stopped printing. The third was missing and it
  is the one that produced a false "finished" 260 seconds early in real use. The rule is now stated:
  if you are deciding on the *absence* of something, `settled` is not sufficient evidence.
- **`exit_code` answers whether the process ended, not whether the work succeeded.** All eight
  one-shot dispatches returned 0, including runs whose conclusions the caller later had to correct.
  The field was behaving correctly and the documentation never said what it meant. Renaming it would
  convey the same information at the cost of breaking every existing caller.

### Not fixed, deliberately

- **Polling `--screen` can return a half-painted frame.** The most important finding in the report,
  and it ships unaddressed. Two hypotheses were tested and discarded: comparing consecutive renders
  measured *worse* than the status quo — 13 torn frames out of 20 against 11 — because a cyclic
  painter rarely renders the same frame twice, so it times out and returns the torn frame anyway;
  and the renderer's tail window cannot drop a screen clear, because a cut that removes the clear
  removes everything before it too. Redefining it on quiescence could not reproduce the tear at all,
  the identical child giving 11/20 once and 0/20 twice, which means the harness is not measuring
  what it appears to. A fix that fails silently toward "looks done" would be worse than a documented
  limitation. A reproducer has been requested.

### Internal

- `Session::Transcript` extracted from `SessionCommand`, which had reached 930 lines with a third of
  it on one subject: reading the durable NDJSON log, cursor arithmetic across rotation, search and
  screen rendering. Keeping the dropped-byte count on the object rather than threading it through
  every call is what makes the cursor arithmetic hard to get wrong — four methods each took it as an
  argument and each had to remember what it meant. No behaviour change; `session_command.rb` 930 →
  853.

## [v0.6.0] - 2026-08-15

A fix release. Everything here was found by *running* rune — driving real agent CLIs and watching
processes over time — rather than by reading it. Two of the bugs were in code added earlier in the
same week, and one was reported from real use.

### Fixed

- **A session's memory and disk both grew without bound, for as long as the session ran.** A
  persistent session is the whole feature, so this mattered most where it was least visible.
  Resident memory tracked output one-for-one — 27MB to 69MB in eighty seconds at 500KB/s — because
  the supervisor held every byte the child had ever produced. It now keeps a bounded window and
  memory plateaus: over one 150-second run the last 60 seconds added 30MB of output and 0.16MB of
  memory. The transcript **file** had the same problem and was worse, since memory is reclaimed when
  a supervisor exits and a file is not: nothing pruned it, and `archive` moved it rather than
  removing it, so a 150-second run left 80MB behind permanently. It now rotates, keeping the recent
  tail. Cursors are unaffected — a `truncated` event records what was dropped, so a cursor still
  names the same position in the stream and `read` reports `dropped_bytes` rather than quietly
  returning less than was asked for.
- **Rotation itself then cost more memory than the growth it prevented.** Caught by running two
  sessions in conversation for 45 minutes and 4176 turns: memory sat at 145MB until the first
  rotation and jumped to 374MB the instant it ran. Rotation now seeks to the cut point rather than
  scanning what it drops, reads the byte count each event already records instead of parsing the
  event, and copies with `IO.copy_stream`. One rotation went from **+229MB to +0.1MB**. Worth
  recording that the obvious fix — streaming the lines but still parsing them — still cost 96MB and
  would have shipped had it not been measured again.
- **An attachment reported both that the session was still running and that it had ended, in the
  same exit.** Reported from real use against a grok session. The note fired whenever an attachment
  had been established rather than only when the human actually detached. A deliberate detach now
  says so and exits 0; an attachment that ended because output stopped says that instead, exits 1,
  and points at `rune session list` rather than asserting a cause it cannot know.
- **Six defects found by a read-only council review** of 0.5.0 — grok on the renderer, kimi on the
  send path, agy on teardown, one lens each. The renderer printed the byte after any escape it did
  not recognise, so `ESC D` rendered a literal `D`; it discarded cursor save/restore under a comment
  claiming the ignored sequences could not move the cursor; and it left the last-column cursor in a
  state no terminal uses, so backspace, `CUB`, line feed and `EL` all read it wrong. `VPA`, the
  insert/delete/erase-character family and line insert/delete/scroll are now implemented, and
  vertical tab and form feed are motion rather than text. On the send path, an outstanding terminator
  could be appended to still-queued text, putting both in one read — the exact coalescing the
  terminator delay exists to prevent — and a send could be settled before its own input had been
  submitted. On teardown, `stop` force-killed before the graceful path could run, so an in-flight
  send's caller got a dropped connection instead of its output and the control socket was left on
  disk; a killed session recorded `exit_code: 0` as though it had exited cleanly; and a
  process-group kill was skipped whenever the group leader had already exited, orphaning exactly the
  workers it was meant to reap.

### Changed

- `Session::PendingSend` now holds the settle decision, which the supervisor previously carried
  inline. Four review rounds had found defects in that logic, and none of them needed a pty to
  demonstrate yet none could be demonstrated without one; it is now testable on its own.
- CI installs a pinned `fledge` release asset instead of resolving "latest" through the
  unauthenticated GitHub API, which is rate-limited per IP and shared between runners. Four CI runs
  had been lost to `could not determine latest version`, each looking like a real failure.

### Documentation

- `rune session` is in the README at last — a capability entry and a worked example of driving one
  agent from another. Every command in that section was run before it was written.
- `docs/sessions.md` covers `--screen`, the bounded transcript, and every flag a reply can carry,
  with what each should make a caller do.
- Both record what running many sessions at once costs: about 23MB and 27 descriptors each, flat at
  24 and at 60 concurrent sessions. Concurrency itself held — 60 simultaneous starts, every send
  reaching its own session, nothing left running afterwards, and 30 simultaneous unnamed starts
  producing 30 distinct codenames.

## [v0.5.0] - 2026-08-15

Found by dogfooding: driving real agent CLIs through `rune session` and measuring what came back,
rather than reading the code. Every fix below was reproduced against a live agent before it was
written, and every regression test was checked against the unfixed code first.

**Upgrade from 0.4.0 is strongly recommended** — 0.4.0 silently fails to deliver most prompts to
Claude Code.

### Fixed

- **Prompts longer than about 64 characters were typed into an agent's composer and never sent**,
  while `rune session send` reported a clean `settled: true`. An agent prompt is almost always
  longer than that, so for the one thing this feature exists to do — an agent CLI driving another —
  sends were silently not being delivered to Claude Code. A TUI treats a large chunk arriving in one
  read as a paste, and a carriage return inside a paste is a newline in the composer rather than
  Enter. The terminator is now written separately, after the text has drained. Measured against
  Claude Code: before the fix only 61 characters submitted and 82 did not; after it, every length
  tried up to 262 submits, and grok and agy are unaffected either way.
- **A `--wait-for-regex` pattern could wedge the supervisor past its own timeout.** The match runs
  on the supervisor's only thread, so a catastrophically backtracking pattern blocked the event loop
  outright — it could not pump the pty, answer `stop`, or even check the send's own `--timeout-ms`,
  because that check lives in the same loop. Reproduced with `(a+)+\1$`, where the send was still
  blocked long after its 8s deadline. A match now gets a bounded budget where Ruby supports one, and
  exceeding it abandons the pattern with `regex_timed_out: true`. Ruby memoizes most textbook
  catastrophic patterns since 3.2, but not those using backreferences; **Ruby 3.0 and 3.1 have no
  per-`Regexp` timeout and remain exposed**, which is now a stated limitation.
- **A supervisor that died said nothing about why.** `meta.json` still read `state: running` with no
  exit code, no exit event was logged, and `supervisor.log` was empty. The cause is now written to
  the transcript as a `crash` event and to stderr, and the session is marked finished with exit code
  70 whatever path teardown took.
- **A bytes-vs-characters bug killed live agent sessions within a handful of turns.** Multibyte
  output arriving inside the echo grace window asked for more characters than existed and raised,
  taking the supervisor and the agent process with it — reproducible within 2–4 turns, and an agent
  TUI paints spinners and box-drawing rules constantly. Echo tracking now counts characters
  throughout, which also stops a non-ASCII prompt from eating the first characters of a reply.
- Erasing to the start of a line now includes the cell under the cursor, per ECMA-48, so a repainted
  line no longer keeps one character it should have lost.
- The terminator delay now holds under backpressure. It is measured from the last text byte actually
  going out rather than from when the send arrived, so a write delayed by a full pty buffer cannot
  land in the child's next read alongside the text.

### Added

- **`--screen` on `rune session send` and `read`** returns the rendered terminal alongside the byte
  stream. A full-screen agent interleaves its answer with its own repaints, so the byte stream holds
  every frame while the screen holds only what is displayed: grok's 361KB transcript renders to
  1.1KB, claude's 163KB to 2.4KB. Measured against grok, an answer the agent plainly displayed was
  absent from the byte stream 3/3 turns and present in the rendered screen 3/3. Opt-in, and rendered
  in the calling process so the supervisor's event loop is untouched. A cooked-mode shell barely
  changes, because it does not repaint.
- `Parsers::ScreenRenderer`, the terminal replay behind it. Deliberately not a full emulator: it
  implements what decides where text lands — cursor motion, erasing, line discipline — and consumes
  everything else, which by definition cannot change what is on screen.
- `busy_at_send` on a settle reply, reporting that the child was still producing output when the
  send landed.

### Changed

- **`--settle-ms` returns to a default of 800**, reverting the 0.4.0 change. That change was made on
  a measurement that was wrong twice over, and both faults were in the measuring harness rather than
  in settle: the claude figures used a prompt above the length that was never being submitted at
  all, and the grok figures searched the byte stream for an answer that repaints had split.
  Re-measured with both corrected and detection moved to the rendered screen, the reply was the
  answer to the question actually asked in **27/27 claude turns and 18/18 grok turns, at every
  window including 800ms** — with the longer window costing up to double the latency per call and
  buying nothing. The "previous turn's answer" failure that 0.4.0 documented as settle's
  characteristic weakness was an artifact and has not been observed since.

## [v0.4.0] - 2026-08-15

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

- Examples are split by audience: `examples/agents/` (structured, programmatic) and
  `examples/humans/` (interactive programs meant to be driven from a terminal). Each folder has a
  README, and new examples cover the library surface, multi-session fan-out, failure handling,
  driving rune as a subprocess without loading the library, and a stand-in agent REPL that costs no
  API quota. The repository is now Ruby end to end — no shell scripts remain.
- CI no longer runs the Augur risk gate or Attest provenance verification, and `spec-sync` runs
  without `--strict`/`--stale`. The contract itself — specs matching code, coverage staying
  complete — is the part worth gating on; the rest was rejecting work for bookkeeping reasons
  rather than for drift between specs and code. To be revisited when spec-sync 6 lands, which
  reworks the change-verification model. The spec-sync job also no longer waits on the Ruby matrix:
  the two check different things and neither needs the other, so running them side by side returns
  a result in ~90s instead of ~2m40s. `scripts/trust_range.sh` and
  `scripts/squash_attest_forwards.sh` existed only to make those gates non-vacuous and are removed
  with them.

- **`--settle-ms` now defaults to 3000 rather than 800**, on measurement rather than taste. Driving
  Claude Code through 27 turns (three task shapes × three trials × three windows), the reply was the
  answer to the question actually asked in 5/9 at 800ms, 8/9 at 3000ms and 8/9 at 6000ms. The
  failure at 800ms was almost never a truncated answer — it was the *previous* turn's answer,
  returned whole and well-formed, which a caller cannot distinguish from a correct reply. 6000ms
  bought nothing over 3000ms and cost 2.5s per call. Sends against fast, non-agent children (a
  cooked shell) should pass a smaller `--settle-ms` explicitly; the default is now tuned for the
  agent CLIs this feature exists to drive.
- A send issued while the child was still producing output reports `busy_at_send: true` — the case
  where a reply is most likely to be the previous turn's answer. Reported rather than prevented:
  deferring the write until the child goes quiet needs another deferred state in the event loop.

### Fixed

- **A session driving a real agent CLI died within a handful of turns.** `echo_still_arriving?`
  bounded its loop by *byte* length while indexing by *character*, so any multibyte output arriving
  inside the echo grace window asked for more characters than existed, got `nil`, and
  `start_with?(nil)` raised — killing the supervisor and taking the agent process with it. An agent
  TUI paints spinners and box-drawing rules constantly, so this was the normal case for exactly the
  targets sessions exist to drive: reproducible within 2–4 turns, three runs out of three, and
  12/12 rounds clean after the fix. `beyond_echo` had the same mix-up in the other direction —
  advancing past the echo by its byte length overshot for any non-ASCII prompt and silently ate the
  first characters of the reply. Both now count characters throughout. Found by dogfooding; three
  rounds of independent code review did not.
- **A supervisor that died said nothing about why.** `meta.json` still read `state: running` with no
  exit code, no exit event was written to the transcript, and `supervisor.log` — the supervisor's
  own stderr — was empty, so every later command reported a session that was not there and nothing
  named the cause. The supervisor now records a `crash` event with class, message and backtrace to
  the transcript and to stderr, and exits `70` (sysexits `EX_SOFTWARE`, distinct from any status the
  child could return). Teardown marks the session finished no matter how it got there, so no path
  leaves a session claiming to be running.
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
