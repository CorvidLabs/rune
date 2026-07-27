# rune 0.2.0 milestone

Tracking issue for the next `rune` release. Scope is deliberately narrow: harden the PTY runner
and parser APIs that shipped in 0.1.x, close the documentation gap, and keep the CorvidLabs trust
toolchain green — not new commands.

## Scope

- [x] **Configurable PTY timeout** — `PTYRunner#initialize` already exposed `timeout_seconds:`;
      `rune run` now exposes it on the CLI via `--timeout=SECONDS` (recognized only before a `--`
      separator, so it never collides with the wrapped command's own flags). See
      `specs/pty_runner/pty_runner.spec.md`.
- [ ] **PTY fallback / non-PTY environments** — `PTYRunner` currently hard-depends on `PTY.spawn`
      (via Ruby's `pty` stdlib), which is unavailable on Windows and can be unavailable in some
      sandboxed/containerized CI environments. Decide and implement a fallback strategy before
      0.2.0 ships:
      - Detect `PTY` unavailability and fall back to a plain `Process.spawn` + pipe capture
        (loses TTY-dependent behavior of the wrapped command, but keeps `rune run` functional), or
      - Document the platform constraint explicitly in the README/gemspec and fail fast with a
        clear `Result.failure` instead of an unhandled `LoadError`/`NotImplementedError`.
      Either way, add coverage in `spec/rune/pty_runner_spec.rb` for the no-PTY code path.
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
      `spec/rune/pty_runner_spec.rb` and `spec/rune/signal_handler_spec.rb`.
- [x] **`Script.new { ... }` no longer silently produces a broken empty script** — only
      `Script.define { ... }` used to `instance_eval` the block; `Script.new` accepted and
      discarded a block with no error, so the natural Ruby idiom silently built an empty script,
      surfacing only as a confusing downstream PTY timeout. `Script#initialize` now `instance_eval`s
      its block directly; `.define` is a thin wrapper over `.new`. See `spec/rune/script_spec.rb`.
- [ ] **Trust toolchain verification** — Run and pass the full trust gate ahead of tagging 0.2.0:
      `fledge run test`, `fledge run lint`, `fledge run spec-check`, `fledge trust verify`. Treat
      an Augur `block` verdict or a failed Attest provenance check as a hard stop per `AGENTS.md`.

## Non-goals for 0.2.0

- New subcommands beyond `run`/`version`.
- Changes to the `Result`/`Renderer` JSON envelope shape (breaking for existing agent consumers).
- Adding runtime dependencies — `rune` stays stdlib-only.

---

# Release checklist

Gates that must all be green before `rune` 0.2.0 is tagged and published:

- [ ] **Stable API freeze** — `PTYRunner`, `TableParser`, `KeyValueParser`, `TextSanitizer`,
      `Result`, and the `rune run`/`rune version` CLI surface are frozen for 0.2.0. Any further
      change before tagging requires updating the relevant `specs/*.spec.md` contract in the same
      change.
- [ ] **PTY edge cases documented/fixed** — Non-PTY fallback behavior (see milestone item above)
      is either implemented or explicitly documented as an unsupported-platform limitation; no
      silent crashes on Windows/sandboxed CI.
- [ ] **Dogfooding (internal + external)** — `rune` used for at least one real task inside another
      CorvidLabs repo via `fledge plugins install rune` (internal), and at least one external
      user/agent run reported back before tagging.
- [x] **CorvidLabs site tools page live** — `rune` has a full `/rune/` landing page and
      `/rune/docs/` section, registered in the site's project catalog and top nav alongside
      `fledge`, `augur`, `attest`, and `spec-sync` (`CorvidLabs/site#225`).
- [ ] **Trust toolchain green** — `fledge trust verify` passes with no unresolved Augur `block`
      verdicts and Attest provenance recorded for the release commit.
