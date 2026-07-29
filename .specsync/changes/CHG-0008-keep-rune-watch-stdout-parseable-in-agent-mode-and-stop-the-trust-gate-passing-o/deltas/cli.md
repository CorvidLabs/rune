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

### SPEC SECTION Behavioral Examples

- Running `rune version` in a terminal prints human-formatted version info
- Running `rune version --json` reports the current `Rune::VERSION` in the success envelope
- Running `rune version --ndjson` prints `{"event":"result","status":"ok",...}`
- Running `rune run -- tool --json` passes `--json` to `tool` instead of consuming it globally
- Piping `rune version | cat` automatically outputs JSON
- Running `rune nonexistent` returns exit code 1 and an error message
- Running the release-version setter repairs one stale version source when the other already matches
- Running `rune watch --json -- CMD` from a terminal writes only the result envelope to stdout and
  the wrapped command's live output to stderr, so `rune watch --json -- CMD 2>/dev/null | jq`
  succeeds; without the split, stdout began with the child's own bytes and failed to parse
