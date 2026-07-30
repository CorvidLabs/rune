## MODIFIED

### SPEC SECTION Invariants
1. Commands never print directly to stdout — they return a `Result`
2. `Result#to_h` always includes a `status` key ("ok" or "error")
3. Non-TTY stdout automatically triggers JSON output (agent mode)
4. `--json` flag forces JSON output regardless of TTY
5. `--ndjson` forces a newline-delimited result envelope; live multi-event streaming is provided by
   `rune watch`.
6. `Result#exit_code` defaults to 0 for success / 1 for failure, but a command can override it via
   `exit_code:` on `Result.success`/`.failure` — e.g. `RunCommand`/`WatchCommand` mirror the wrapped
   command's own exit code, so `rune run -- false` composes correctly with shell `&&`/`||`/
   `set -e` even though the `Result` itself is a success. The override affects only the
   process-level exit status, never `Result#to_h`'s serialized JSON shape.
7. Commands self-register via Ruby class inheritance hooks
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

### SPEC SECTION Error Cases
| Condition | Behavior |
|-----------|----------|
| Unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Command raises exception | Caught and wrapped in `Result.failure`, exit code 1 |
| No command given | Shows help output |
| Help requested for an unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Mixed or repeated help aliases | Consumes every alias, returns help, and exits 0 |
