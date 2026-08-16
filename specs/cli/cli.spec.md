---
module: cli
version: 22
status: active
files:
  - lib/rune.rb
  - lib/rune/cli.rb
  - lib/rune/command.rb
  - lib/rune/result.rb
  - lib/rune/renderer.rb
  - lib/rune/help.rb
  - lib/rune/version.rb
  - lib/rune/commands/version_command.rb
---
# CLI

## Purpose
Core CLI framework for rune. Provides command registration, argument parsing, dual-mode output (human-pretty for terminals, structured JSON for agents, streaming NDJSON), and the base `Command` class that all commands extend. Designed so that every interaction is first-class for both humans and AI agents.

## Public API

| Name | Type | Description |
|------|------|-------------|
| `CLI` | class | CLI router. Class methods: `run(argv)`, `register(command_class)`, `commands`. Instance: `run(argv)`. |
| `Command` | class | Base class for commands. DSL: `name(n)`, `summary(s)`, `usage(text)`, `flag(spec, description)`. Override: `call(args, options)`, `human_render(data, io)`. |
| `Result` | class | Structured result. Class methods: `.success(data, exit_code: nil)`, `.failure(error, data: nil, exit_code: nil)`. Instance: `#success?`, `#failure?`, `#to_h`, `#exit_code`. |
| `Renderer` | class | Output formatter. `#agent_mode?`, `#render(result, human_block:)`. Supports JSON and NDJSON modes. |
| `Error` | class | Base exception reserved for rune-specific library errors. |
| `Rune` | module | Top-level namespace for the library and CLI framework. |
| `register` | class method | Registers a command subclass immediately after its DSL name is declared. |
| `run` | method | Dispatches an argv array, renders its `Result`, and exits with `Result#exit_code`. |
| `commands` | reader | Returns the registered command-name-to-class mapping. |
| `name` | class method | With an argument, declares and registers the CLI name for a `Command` subclass; without one, returns the normal Ruby class name. |
| `summary` | class method | Declares the help summary for a `Command` subclass. |
| `call` | instance method | Command execution contract; subclasses must return a `Result`. |
| `human_render` | instance method | Optional command-specific terminal renderer. |
| `command_name` | reader | Returns the subclass's declared CLI name. |
| `command_summary` | reader | Returns the subclass's declared help summary. |
| `success?` | predicate | Reports whether a `Result` has `:ok` status. |
| `failure?` | predicate | Reports whether a `Result` has `:error` status. |
| `success` | class method | Constructs a successful `Result`, optionally with a process exit override. |
| `failure` | class method | Constructs an error `Result`, optionally with data and a process exit override. |
| `to_h` | instance method | Serializes the stable status/data/error envelope. |
| `exit_code` | instance method | Returns the explicit process exit override or the status-derived default. |
| `status` | reader | Returns the symbolic result status. |
| `data` | reader | Returns the result payload, if any. |
| `error` | reader | Returns the result error message, if any. |
| `agent_mode?` | predicate | Selects structured output for explicit JSON modes or non-TTY output. |
| `render` | instance method | Renders one `Result` in NDJSON, JSON, or human form. |
| `render_event` | instance method | Emits and flushes a named NDJSON event when NDJSON mode is active. |
| `io` | reader | Returns the renderer's output stream. |
| `json_mode` | reader | Reports whether explicit JSON rendering is enabled. |
| `ndjson_mode` | reader | Reports whether NDJSON envelope rendering is enabled. |
| `VERSION` | constant | Current rune release version. |
| `VersionCommand` | class | Returns rune, Ruby, platform, and optional-tool version information. |
| `Commands` | module | Namespace containing concrete CLI command implementations. |
| `usage` | class method | Declares the one-line invocation shape shown by `rune <cmd> --help`. |
| `flag` | class method | Declares one command-specific flag (spec + description) for command help. |
| `command_usage` | reader | Returns the subclass's declared usage line, or nil. |
| `command_flags` | reader | Returns the subclass's declared flags, defaulting to an empty array. |
| `Help` | class | Builds and renders `rune --help`, `rune <cmd> --help`, and `rune help [cmd]`. Class method: `.extract_flag!(args)`. Instance: `#overview`, `#for_command(name)`, `#render(data, io)`. |
| `FLAGS` | constant | Tokens (`--help`, `-h`) recognized as a help request before the first `--`. |
| `GLOBAL_FLAGS` | constant | Flags that apply to every command, rendered under "Global flags" and returned in every help payload. |
| `extract_flag!` | class method | Removes every help alias from the pre-separator argv in place and reports whether any were present. |
| `overview` | instance method | Builds the all-commands help `Result`. |
| `for_command` | instance method | Builds one command's help `Result`, or a structured failure for an unknown name. |
| `render_command` | internal method | Renders one command's usage and flag list for a terminal. |
| `render_flags` | internal method | Renders an aligned flag/description list. |

## Invariants

1. Commands never print directly to stdout — they return a `Result`
2. `Result#to_h` always includes a `status` key ("ok" or "error")
3. Non-TTY stdout automatically triggers JSON output (agent mode)
4. `--json` flag forces JSON output regardless of TTY
5. `--ndjson` forces a newline-delimited result envelope; successful final results use
   `event: "result"` and failures use `event: "error"`. Live multi-event streaming is provided by
   `rune watch`.
6. `Result#exit_code` defaults to 0 for success / 1 for failure, but a command can override it via
   `exit_code:` on `Result.success`/`.failure` — e.g. `RunCommand`/`WatchCommand` mirror the wrapped
   command's own exit code, so `rune run -- false` composes correctly with shell `&&`/`||`/
   `set -e` even though the `Result` itself is a success. The override affects only the
   process-level exit status, never `Result#to_h`'s serialized JSON shape.
7. A command registers synchronously when its `name` DSL declaration runs. Registration does not
   install a `TracePoint`; unnamed subclasses remain unregistered without leaving global
   instrumentation enabled. Calling `.name` without a DSL argument preserves Ruby's class-name
   reflection.
8. Unknown commands return a structured error, never crash
9. `--json` and `--ndjson` are rune-global only before the first `--` separator. Identical tokens
   after the separator are preserved as wrapped-command arguments.
10. `Rune::VERSION`, `plugin.toml`, and the release tag identify the same semantic version before a
    package can be published. The release ref is an exact Git tag whose commit is reachable from
    `origin/main`.
11. In agent mode, stdout carries the structured envelope and nothing else: the *complete* stdout of
    any command parses as exactly one JSON document (or, under `--ndjson`, one JSON line per
    emitted event). A command that also produces side-effect output while it runs — currently only
    `rune watch`'s live passthrough — must route that output to stderr whenever `--json`/`--ndjson`
    is set or stdout is not a TTY. This is enforced end-to-end against the real `bin/rune`
    executable for every registered command in every agent output mode, asserting over whole
    stdout rather than a substring, because a substring assertion passes against interleaved
    output and previously did.
12. `--help` and `-h` are accepted at the top level (`rune --help`) and per command
    (`rune run --help`), and `rune help <command>` is equivalent. Command help never executes the
    command — `rune run --help` previously spawned `--help` in a pty and reported exit 127.
    Like `--json`/`--ndjson`, they are recognized only before the first `--`, so a wrapped
    command's own `--help` is passed through untouched (invariant 9).
13. Help is a normal `Result`, so it is available in agent mode: `rune <cmd> --help --json`
    returns the command's `usage` string and `flags` list as data. Every flag a command parses is
    declared on that command via the `flag` DSL, so the CLI surface is discoverable without
    reading `specs/` or scraping the human rendering.
14. Help extraction removes every recognized alias before the first separator. Mixed and repeated
    forms such as `rune --help -h` and `rune --help --help` remain help requests and do not leave
    an alias behind to be resolved as a command.
15. Rendering modes are invocation-local. Reusing one `CLI` instance for help and then a normal
    command resets help, JSON, and NDJSON selection before the second dispatch; no help or output
    flag from an earlier run may affect a later run.
16. Rune writes its final rendered result to stdout for both success and failure. In agent mode this
    keeps one structured channel; in human mode it means redirecting stdout also redirects
    Rune-level errors. Stderr is reserved for operational announcements and live passthrough that
    must not corrupt structured stdout.

## Behavioral Examples

- Running `rune version` in a terminal prints human-formatted version info
- Running `rune version --json` reports the current `Rune::VERSION` in the success envelope
- Running `rune version --ndjson` prints `{"event":"result","status":"ok",...}`
- Running `rune run -- tool --json` passes `--json` to `tool` instead of consuming it globally
- Piping `rune version | cat` automatically outputs JSON
- Running `rune nonexistent` returns exit code 1 and an error message
- Running `rune nonexistent --ndjson` writes
  `{"event":"error","status":"error","error":"Unknown command: ..."}` to stdout
- Redirecting `rune nonexistent >result` captures the human error in `result`; Rune does not split
  final success and failure envelopes across different streams
- Running the release-version setter repairs one stale version source when the other already matches
- Running `rune watch --json -- CMD` from a terminal writes only the result envelope to stdout and
  the wrapped command's live output to stderr, so `rune watch --json -- CMD 2>/dev/null | jq`
  succeeds; without the split, stdout began with the child's own bytes and failed to parse
- Running `rune --help`, `rune -h`, or `rune help` all print the same command overview and exit 0
- Running `rune run --help` prints `rune run [--timeout=SECONDS] [--] <command...>` and exits 0
  without spawning anything
- Running `rune run --help --json` returns `data.usage` and `data.flags` for an agent to read
- Running `rune run -- mytool --help` passes `--help` to `mytool` instead of showing Rune's help
- Running `rune --help -h` returns the overview rather than treating `-h` as a command
- Reusing a `CLI` object for `run --help` and then `version` renders version output normally

## Error Cases

| Condition | Behavior |
|-----------|----------|
| Unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Command raises exception | Caught and wrapped in `Result.failure`, exit code 1 |
| No command given | Shows help output |
| Help requested for an unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Mixed or repeated help aliases | Consumes every alias, returns help, and exits 0 |
| Reused CLI after help | Resets help and output modes, then dispatches and renders normally |

## Dependencies

- Ruby stdlib: `json`
- No external runtime dependencies

## Change Log

- v1: Active spec — CLI framework with dual-mode output and NDJSON envelopes
- v1: Restricted global output-flag extraction to arguments before the first `--`, preserving
  identically named flags for wrapped commands.
| 2026-07-28 | CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery: Adopt and enforce SpecSync 5 for release delivery |
| 2026-07-29 | CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and: Address PR review findings in release synchronization, SDD package coverage, and publish ref validation |
| 2026-07-29 | CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o: Keep rune watch stdout parseable in agent mode and stop the trust gate passing on an empty commit range |
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-07-29 | CHG-0012-restore-full-cli-contract-detail-after-the-help-delta-and-establish-exact-semant: Restore full CLI contract detail after the help delta and establish exact semantic successor coverage |
| 2026-07-29 | CHG-0014-clarify-mixed-help-aliases-and-invocation-local-cli-modes-in-the-exact-cli-contr: Clarify mixed help aliases and invocation-local CLI modes in the exact CLI contract |
| 2026-07-29 | CHG-0015-record-exact-supersession-for-the-committed-cli-help-contract-and-document-cli-r: Finalize the committed CLI help contract and document CLI reuse recovery |
| 2026-07-29 | CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and: Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible |
| 2026-08-14 | CHG-0025-prep-0-3-0-release-bump-version-roll-up-changelog: Bump `Rune::VERSION` to 0.3.0 for the 0.3.0 release prep. No public API or contract change — version constant value only. |
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Register the new `rune session` subcommand by requiring the session module and `SessionCommand` from `lib/rune.rb`. No change to the CLI framework's own public API, output modes, or help contract — the session surface is specified in its own `session` canonical spec. |
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Add persistent named agent sessions: rune session start/send/read/list/stop, backed by a per-session detached supervisor holding the PTY, with send-and-settle so one agent CLI can drive another synchronously |
| 2026-08-15 | CHG-0032-prep-0-4-0-release-bump-version-roll-up-changelog: Prep 0.4.0 release: bump version, roll up CHANGELOG |
| 2026-08-15 | CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full: Render the terminal screen for session send and read, so an agent driving a full-screen agent can find the answer instead of searching every repaint frame |
| 2026-08-15 | CHG-0038-prep-0-5-0-release-bump-version-roll-up-changelog: Prep 0.5.0 release: bump version, roll up CHANGELOG |
| 2026-08-15 | CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class: Extract the pending-send settle machine out of the supervisor into its own class, so the logic four review rounds kept finding bugs in is testable without an event loop |
| 2026-08-15 | CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job: Pin fledge in CI to a release asset instead of resolving latest on every job |
| 2026-08-15 | CHG-0047-prep-0-6-0-release-bump-version-roll-up-changelog: Prep 0.6.0 release: bump version, roll up CHANGELOG |
| 2026-08-15 | CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an: Extract the transcript out of SessionCommand: reconstruction, cursors, search and rendering are one subject |
| 2026-08-16 | CHG-0051-prep-0-7-0-release-bump-version-roll-up-changelog: Prep 0.7.0 release: bump version, roll up CHANGELOG |
| 2026-08-16 | CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it: Fail the release before the tag when provenance is missing, not after it |
| 2026-08-16 | CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha: Four-agent pre-1.0 review: nine bugs fixed, and fifteen documentation claims that were wrong |
| 2026-08-16 | CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail: Turn the provenance gate off, and record why, instead of leaving it to fail |
