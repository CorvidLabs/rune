# rune release roadmap

## 0.2.1 release record

`v0.2.0` shipped on 2026-07-27. The follow-up `v0.2.1` patch packages the PTY, UTF-8, watch-log,
Ruby compatibility, documentation, and trust-gate fixes already merged to `main`.

- [x] Synchronize `Rune::VERSION` and `plugin.toml` at `0.2.1`.
- [x] Add an automated version/tag parity check to local verification, CI, and package publishing.
- [x] Require strict Attest verification from the previous tag through the release tag.
- [x] Add a release lane covering version parity, lint, tests, spec-sync, smoke tests, and gem build.
- [x] Merge the release-prep PR after its CI and review gates pass.
- [x] Attest the resulting commit on `main`, verify `v0.2.0..HEAD`, then create and publish `v0.2.1`.
- [x] Publish `rune` 0.2.1 to GitHub Packages from the verified release tag.
- [ ] Merge the checksum-pinned 0.2.1 formula update in `CorvidLabs/homebrew-tap`.

## 0.2.0 release record

Tracking issue for the next `rune` release. Scope was originally deliberately narrow: harden the
PTY runner and parser APIs that shipped in 0.1.x, close the documentation gap, and keep the
CorvidLabs trust toolchain green — no new commands. That non-goal was explicitly revisited and
overridden once, for `rune watch` (see below): a real, requested capability gap (live interactive
passthrough), not scope creep.

## Scope

- [x] **Configurable PTY timeout** — `PTYRunner#initialize` already exposed `timeout_seconds:`;
      `rune run` now exposes it on the CLI via `--timeout=SECONDS` (recognized only before a `--`
      separator, so it never collides with the wrapped command's own flags). See
      `specs/pty_runner/pty_runner.spec.md`.
- [x] **PTY fallback / non-PTY environments** — `require 'pty'` at load time meant *any* rune
      command (even `version`) crashed at boot with a bare `LoadError` on a platform without the
      `pty` stdlib (Windows, some sandboxed CI). The require is now rescued; `PTYRunner.pty_available?`
      reports the result, and `PTYRunner#run` returns a clear `Result.failure` instead of raising
      when unavailable, while every other command keeps working. This is the "fail fast with a
      clear error" option, not a working `Process.spawn` fallback — `rune run` genuinely doesn't
      function without a PTY on 0.2.0; a real non-PTY execution path (losing TTY-dependent behavior
      but staying functional) remains a possible future enhancement, not done here (explicitly
      descoped — not worth it without an actual Windows/restrictive-CI user). Extended to also
      cover the OS refusing pty allocation at *runtime* (`Errno::ENXIO`/`EMFILE`/`ENFILE`/`EPERM`
      — sandbox/container denial, pty exhaustion), not just `require 'pty'` failing at load time.
      Covered in `spec/rune/pty_runner_spec.rb`.
- [x] **TableParser delimiter option** — `TableParser.parse(text, format:)` now accepts `:auto`
      (default heuristic), `:pipe`, or `:space` to bypass auto-detection. Heuristic limitations
      are documented in `specs/parsers/parsers.spec.md` under "Known Limitations."
- [x] **Docs updates** — Added `docs/getting_started.md` (output modes, `rune run`, timeouts,
      parsers, all with real command output) and linked it from `README.md`.
- [x] **Signal forwarding actually works** — `SignalHandler` previously called `Process.kill`
      directly from inside the `Signal.trap` handler while the main thread was blocked in
      `PTYRunner`'s read loop; this did not reliably terminate the wrapped child on every
      Ruby/platform combination, despite being fixed in appearance (#2, "add signal forwarding").
      `SignalHandler.with_traps` now only records which signal arrived from inside the trap, and
      yields a `forward_signal` callable that `PTYRunner#read_pty_stream` polls from ordinary code
      between reads (using `reader.wait_readable(0.2)` instead of an indefinite blocking
      `readpartial`). Verified via a deterministic in-process self-signal regression test in
      `spec/rune/pty_runner_spec.rb` and `spec/rune/signal_handler_spec.rb`, and confirmed in a real
      (non-sandboxed) terminal: `rune run --json -- sleep 30` + Ctrl+C returned in ~2.4s with
      `exit_code: 130`, not after the full 30s.
- [x] **`Script.new { ... }` no longer silently produces a broken empty script** — only
      `Script.define { ... }` used to `instance_eval` the block; `Script.new` accepted and
      discarded a block with no error, so the natural Ruby idiom silently built an empty script,
      surfacing only as a confusing downstream PTY timeout. `Script#initialize` now `instance_eval`s
      its block directly; `.define` is a thin wrapper over `.new`. See `spec/rune/script_spec.rb`.
- [x] **`rune run` exit code composability** — the process itself always exited `0`/`1` based on
      whether *rune* succeeded at capturing a run, never reflecting the wrapped command's own exit
      code, so `rune run -- false && echo unreachable` was always reachable. `Result` now accepts an
      `exit_code:` override (used only for the process-level `Result#exit_code`, not serialized into
      the JSON envelope — no breaking change to the `{"status":...,"data":{"exit_code":...}}` shape),
      and `PTYRunner` sets it to the wrapped command's own exit code. See `spec/rune/result_spec.rb`.
- [x] **`--timeout` input validation** — `--timeout=0` previously meant "no timeout" (Ruby's
      `Timeout.timeout(0)` semantics leaking through unvalidated) and `--timeout=abc` silently got
      glued into the executed command string instead of erroring. `RunCommand` now requires a
      positive integer and fails fast with a clear message otherwise. See
      `spec/rune/commands/run_command_spec.rb`.
- [x] **`PromptDetector` false positive on progress output** — `"Building... 45%"` and similar
      digit-percent progress lines were misdetected as interactive tcsh-style `%` prompts by the
      trailing `[>$%#...]` catch-all pattern. Added a `FALSE_POSITIVES` exclusion for a digit
      immediately before a trailing `%` (trade-off: a real tcsh prompt on a hostname ending in a
      digit is now missed, judged rare relative to how common progress output is).
- [x] **Non-UTF-8 wrapped-command output crashed `rune run`** — found via real internal dogfooding
      (installed rune as a fledge plugin in `attest` and ran its Swift test suite through
      `rune run`): `swift test`'s output tripped `Encoding::CompatibilityError: incompatible
      encoding regexp match (UTF-8 regexp with BINARY (ASCII-8BIT) string)`, since raw PTY reads
      aren't reliably tagged as valid UTF-8 but every downstream regex (prompt detection, ANSI
      stripping, `wait_for`) is. Each chunk is now force-encoded to UTF-8 and scrubbed of invalid
      byte sequences immediately after `readpartial`. Verified against the real `swift test`
      command that triggered it (138 tests, 0 failures, full structured output) and covered by a
      regression test in `spec/rune/pty_runner_spec.rb`.
- [x] **A literal `--` inside the wrapped command was silently eaten** — found via real *external*
      dogfooding (`fledge rune run --json -- cargo clippy --workspace --tests -- -D warnings` in
      `merlin`): `RunCommand` stripped every `--` token from the args array, not just rune's own
      leading separator, corrupting any wrapped command that uses `--` itself (cargo, npm, git all
      do). Now only the first, leading `--` (rune's own) is dropped; any further `--` the wrapped
      command's own argv contains is preserved untouched. Covered in
      `spec/rune/commands/run_command_spec.rb`.
- [x] **`rune watch` — live interactive passthrough** — a genuinely new capability, not a bugfix:
      `rune run` buffers a command's entire output and only returns it once finished, with no live
      stdin forwarding at all. `rune watch -- <command>` puts the terminal in raw mode, forwards a
      human's keystrokes to the child live, streams output to the screen as it happens, and
      simultaneously logs every chunk as an NDJSON event (`start`/`output`/`exit`) so an agent can
      tail the session in real time. Implemented as a new `PTYWatcher` class (not a `PTYRunner`
      mode — `PTYRunner`'s contract stays frozen) with injectable `input`/`output`/`log` so the
      forwarding/logging mechanics are unit-testable without a real controlling terminal (a fake
      `#tty? => true` object plus `IO.pipe`s drives a real interactive child end-to-end in
      `spec/rune/pty_watcher_spec.rb`). `examples/demo_tui.rb` ships as a small interactive program
      to actually try it against — and doing exactly that, live, immediately surfaced two real
      issues fixed the same session: an unhandled `Interrupt` on Ctrl+C dumped a raw Ruby backtrace
      (now rescued, exits 130 cleanly), and the original stderr-by-default event log interleaved
      JSON noise directly into the human's live terminal view, making the session unreadable. The
      log now defaults to an announced temp file instead (`--log=PATH` still overrides it, and
      `--log=/dev/stderr` still gets the old behavior back if genuinely wanted). Its top-level menu
      was also rebuilt as a real arrow-key selector (↑/↓ + Enter, `q` to quit, `io/console#getch`)
      instead of type-a-number-and-press-Enter, at the user's request, specifically to exercise raw
      single-byte/escape-sequence forwarding — the thing rune's byte-level input handling actually
      has to get right, which a purely line-buffered menu never touches. Covered end-to-end (down
      arrows, Enter, a line-based sub-prompt, more arrows, Enter again, an interrupt mid-selector,
      and a lone Escape key that must time out rather than hang) in `spec/rune/pty_watcher_spec.rb`.
      See `specs/watch/watch.spec.md`.
- [x] **Root-caused `rune watch` never actually entering raw mode in real usage** — found via live
      terminal dogfooding: arrow keys showed up as literal `^[[B`/`^[[A` text and `getch` blocked
      forever with no output. `lib/rune/pty_watcher.rb` never `require 'io/console'` itself — only
      `examples/demo_tui.rb` (the *child* process) did — so the real CLI's own `$stdin` in the
      *parent* process never gained `#raw`/`#getch` at all, silently leaving the terminal in cooked
      mode (which both locally echoes keystrokes and line-buffers at the kernel level, swallowing
      any input without a trailing newline). Fixed by requiring `io/console` unconditionally in
      `pty_watcher.rb` (rescued on `LoadError`, same pattern as `pty_runner.rb`'s `pty` rescue) and
      rewriting the raw-mode entry point to try `input.raw(&block)` directly, rescuing
      `Errno::ENOTTY`/`NoMethodError` to fall back for non-tty test doubles — `respond_to?(:raw)`
      stopped being a valid tty-vs-pipe check the moment `io/console` is required, since it
      monkey-patches `#raw` onto every `IO` object, tty-backed or not. Confirmed fixed via the
      user's own live retest (clean arrow-key navigation, no literal escape sequences). Also fixed,
      found by the same live retest with `RUNE_DEMO_DEBUG=1` tracing on: `examples/demo_tui.rb`'s
      menu redraw appeared to scroll/duplicate instead of updating in place, because its
      cursor-up-N-lines math only accounted for the menu's own lines, not the debug-trace lines
      printed between redraws — now tracked and folded into the cursor-up count. A further live
      retest (after both of the above were fixed and confirmed) showed the *within-round* redraw
      math was correct but each *round* (menu → action → back to menu) still left the previous
      round's banner/menu/output sitting in scrollback with a fresh block appended below —
      technically working, but reading as an ever-growing pile of duplicate "Use ↑/↓..." headers
      rather than a bug. `select_menu_action` now clears the screen and redraws the banner + menu
      fresh each round instead, so it reads as one persistent app screen.
- [x] **Clearing the screen every round hid each action's own output entirely** — a live retest of
      the screen-clear fix above showed the table/progress/confirm/name results flashed and vanished
      in the same tick, since the outer loop looped straight back into `select_menu_action`'s
      clear+redraw with no pause. Added a `press_any_key` prompt after every action except `:quit`,
      so the result is actually readable before the next round clears it.
- [x] **`rune watch`'s closing duration was raw milliseconds even for multi-second/-minute
      sessions** (e.g. `78104.43ms`) — unreadable at the scale a *watched* session (as opposed to
      `PTYRunner`'s usual sub-second commands) actually runs. `WatchCommand#human_render` now scales
      the unit to the duration (ms under a second, seconds under a minute, `Mm Ss` under an hour,
      `Hh Mm Ss` beyond that) with the exact seconds always shown alongside in parentheses.
- [x] **Fixed a real, reproducible race in the SIGINT-during-raw-selector spec** (not the
      previously-documented rare system-load flake) — found while re-verifying after the fixes
      above: a fixed `sleep 0.3` before signaling raced the child `ruby examples/demo_tui.rb`
      process's own boot/require time, and under load the signal sometimes arrived before the child
      had even reached its `loop do ... rescue Interrupt`, so it died via Ruby's default
      uncaught-Interrupt exit (1) instead of the expected 130 — reproduced directly outside RSpec to
      confirm before fixing. The test now polls the child's actual captured output for the rendered
      menu before signaling, removing the race instead of tuning the sleep.
- [x] **Two more live-retest findings on the demo/closing message** — the blinking terminal cursor
      visibly jumping to wherever the last redraw print landed, on every arrow press, read as a
      glitch; `examples/demo_tui.rb`'s selector loop now hides it (`\e[?25l`) for the duration of the
      redraw loop and restores it (`\e[?25h`, via `ensure` so it survives Ctrl+C) once control leaves
      the selector. Separately, `format_duration`'s parenthetical raw-seconds suffix was pure noise
      below a minute (`"44.7s, 44.71s"` — the same figure restated) since a plain seconds value is
      already exact; the parenthetical now only appears for the coarser `Mm Ss`/`Hh Mm Ss` forms,
      where it actually adds precision the coarse figure alone doesn't have.
- [x] **`rune watch`'s closing message reports duration and the event log path, not just the exit
      code** — `PTYWatcher`'s `Result#data` now includes `duration_ms` (matching `PTYRunner`'s
      convention), and `WatchCommand#call` folds the actual `log_path` used into the returned
      `Result` before handing it back (its `human_render` runs on a *separate* `Command` instance
      per `CLI#render_result`, so this can't travel through instance state).
- [x] **Substantially expanded test coverage** — 57 → 135 RSpec examples; line coverage 88.5% →
      98.3%, branch coverage 72.9% → 81.8% (SimpleCov added as a dev dependency, opt-in via
      `COVERAGE=1 bundle exec rspec`, `.gitignore`d output). Filled real, previously-untested gaps
      driven by the actual coverage report rather than guesswork: `Command`'s `NotImplementedError`
      and auto-registration, `CLI`'s `--version`/`-v` resolution, bare-argv-defaults-to-help,
      human-mode rendering dispatch (`help_human_render` and per-command `#human_render`, both
      previously completely untested), an unhandled exception inside a command's `#call` being
      caught, and `CLI.run`'s class-level entry point; `RunCommand`/`VersionCommand#human_render`;
      a dedicated `PromptDetector` spec (previously only exercised indirectly through
      `PTYRunner#detect_prompt?`); `TableParser`'s single-word-header path and its
      overflow-beyond-header-count rejoin; `SignalHandler`'s dead-pid-forward and invalid-signal
      rescue branches; `PTYRunner`'s permission-denied (real non-executable file), real timeout,
      generic-error, `write_input` failure, and `Script` `:pause`-step paths. Remaining gaps are
      genuinely hard to simulate rather than neglected: a `TracePoint`-based registration hook
      SimpleCov can't see inside, real raw-terminal-mode ioctls (same class of limitation as the
      Ctrl+C verification above — needs an actual controlling terminal), and a couple of
      `Errno::ECHILD`/`PTY::ChildExited` process-reaping races.
- [x] **Trust toolchain verification** — Ran and passed the full trust gate ahead of tagging 0.2.0:
      `fledge run test`, `fledge run lint`, `fledge run spec-check`, `fledge trust verify`. Treat
      an Augur `block` verdict or a failed Attest provenance check as a hard stop per `AGENTS.md`.

## Non-goals for 0.2.0

- New subcommands beyond `run`/`version`/`watch` (the latter added deliberately, see above).
- Changes to the `Result`/`Renderer` JSON envelope shape (breaking for existing agent consumers).
- Adding runtime dependencies — `rune` stays stdlib-only (`rune watch` uses `io/console`, itself
  Ruby stdlib).
- A real non-PTY execution fallback (see the PTY-fallback item above) — descoped, not worth the
  complexity without an actual Windows/restrictive-CI user.

---

# 0.2.0 release checklist

Historical gates completed before `rune` 0.2.0 was tagged and published:

- [x] **Stable API freeze** — `PTYRunner`, `PTYWatcher`, `TableParser`, `KeyValueParser`,
      `TextSanitizer`, `Result`, and the `rune run`/`rune version`/`rune watch` CLI surface are
      frozen for 0.2.0. Any further change before tagging requires updating the relevant
      `specs/*.spec.md` contract in the same change.
- [x] **PTY edge cases documented/fixed** — Non-PTY fallback behavior (see milestone item above)
      is explicitly documented as an unsupported-platform limitation; no silent crashes on
      Windows/sandboxed CI (other commands keep working, `rune run` fails clearly).
- [x] **Internal dogfooding** — `fledge plugins install`ed from local path into `attest` (a
      separate CorvidLabs repo), then used `fledge rune run --json -- swift test` for a real task.
      This is exactly how it surfaced the non-UTF-8 output bug above — real dogfooding, not a
      synthetic exercise.
- [x] **External dogfooding** — ran `fledge rune run --json -- cargo clippy --workspace --tests --
      -D warnings` and `cargo test` against `merlin` (a Rust/cargo project, a different tech stack
      than `attest`'s Swift) from a real, unsandboxed terminal. This is exactly how the `--`
      passthrough bug above was found.
- [x] **CorvidLabs site tools page live** — `rune` has a full `/rune/` landing page and
      `/rune/docs/` section, registered in the site's project catalog and top nav alongside
      `fledge`, `augur`, `attest`, and `spec-sync` (`CorvidLabs/site#225`).
- [x] **`rune watch` dogfooded against a real third-party interactive TUI** — `rune watch --
      fledge plugins search --interactive` (a genuinely different Rust program from
      `examples/demo_tui.rb`: a live GitHub-search spinner, type-ahead fuzzy filtering rendered
      character-by-character, arrow-key list navigation, and a nested y/n confirmation sub-prompt)
      worked end-to-end from a real terminal — selection, install confirmation, and a clean
      non-zero exit on cancel, with the closing message reporting exit code, plain-seconds
      duration, and the event log path exactly as designed.
- [x] **`PromptDetector` false-positive on a `<placeholder>` example line** — found via the same
      dogfooding: `rune run --json -- fledge plugins search rune` (a command that ran to
      completion and printed no prompt at all) reported `prompt_detected: true`, because
      `PTYRunner` scans every line of output for a prompt (not just the last), and the closing
      `Install with: fledge plugins install <owner/repo>` line ends in a bare `>`, which the
      trailing `[>$%#...]` prompt fallback pattern doesn't distinguish from a real shell prompt
      terminator. Added a `<...>`-ending-line exclusion to `FALSE_POSITIVES`.
- [x] **Trust toolchain green** — `fledge trust verify` passes; no unresolved Augur `block`
      verdicts; provenance is in progressive mode pending the remote ledger.
- [x] **Stable API freeze** — `PTYRunner`, `PTYWatcher`, `TableParser`, `KeyValueParser`,
      `TextSanitizer`, `Result`, `Script`, and the `rune run`/`rune version`/`rune watch` CLI
      surface are frozen for 0.2.0, with every behavior change in this session's PR reflected in
      the matching `specs/*.spec.md` contract in the same commit.
- [x] **PR #3 automated review triage** — 21 unique findings from the `chatgpt-codex-connector`
      bot across the PR's commit history were individually re-verified against current code (not
      assumed stale or valid). 3 were already fixed by later commits, 2 are documented accepted
      trade-offs (the digit-percent `PromptDetector` exclusion; `SignalHandler` forwarding only the
      first of multiple distinct signals). Of the 16 real findings, 9 were fixed before tagging:
      - Missing `require 'io/wait'` in `pty_runner.rb`/`pty_watcher.rb` — `IO#wait_readable` isn't
        guaranteed autoloaded by `pty`/`io/console` alone; reproduced a raw `NoMethodError` crash
        on Ruby 3.1, inside this gem's own declared `>= 3.0` support range.
      - `rune run --timeout` didn't kill the spawned child on timeout, leaving it running as an
        orphan (confirmed via a real `ps aux` check) — now `SIGKILL`ed and reaped.
      - `PTYWatcher#with_raw_input`'s rescue was scoped broadly enough to silently re-run an
        already-spawned session a second time if anything unrelated raised `NoMethodError` deep
        inside it — narrowed to only fall back when raw-mode entry itself failed.
      - `rune watch --log=` (empty value) silently smuggled the raw flag into the wrapped command's
        argv instead of erroring clearly.
      - `PTYWatcher`'s `duration_ms` used wall-clock `Time.now` instead of a monotonic clock,
        unlike `PTYRunner`'s equivalent metric.
      - `PTYWatcher` didn't preserve the conventional 127/126 exit codes for a missing/
        non-executable wrapped command that `PTYRunner` already returns for the same conditions.
      - `TableParser.parse` validated `format:` only after a short-input early return, so an
        unknown format on empty/single-line input silently returned `[]` instead of raising.
      - `specs/watch/watch.spec.md`'s duration-formatting invariant claimed the exact-seconds
        parenthetical always appears; the actual code (fixed earlier this session, in response to
        live-user feedback) only adds it for the coarser minute/hour forms, as a comma suffix, not
        parentheses — contract corrected to match.
      - `script.rb` and `prompt_detector.rb` had been publicly shipping behavior with no
        `specs/*.spec.md` file coverage at all, since they were added; both now have full
        invariant/example coverage.
      Each fix has a dedicated regression test reproducing the original failure mode. The
      remaining 7 findings are real but larger in scope and deferred — see Known Limitations below.

## Remaining Known Limitations

- **`rune run --ndjson` is an envelope choice, not incremental streaming.** `PTYRunner` buffers
  the whole run and returns one `Result`; `--ndjson` wraps it in an `{"event": "result"|"error"}`
  shape but still emits exactly one line, once the command finishes. Only `rune watch` streams
  live, one NDJSON line per output chunk. `docs/getting_started.md` now describes this accurately
  instead of over-promising incremental output for `rune run`.

## Resolved after 0.2.0

- Global `--json`/`--ndjson` parsing now stops at the first `--`, preserving wrapped-command flags.
- `UTF8StreamDecoder` preserves valid multi-byte characters split across PTY reads.
- `rune watch` mirrors terminal dimensions to the child and tracks later changes while polling.
- Default watch logs are collision-safe, symlink-resistant, owner-only `0600` temporary files.
- The smoke suite's human renderer check now runs inside a real PTY.
- `PTYWatcher` kills and reaps its child when the output sink fails with `EPIPE`.
- Spec-sync is a forced strict 100%-coverage gate locally and in CI; risk and provenance actions
  are no longer allowed to fail silently.
- CI tests every declared Ruby minor from 3.0 through 4.0 before the single trust job runs.
