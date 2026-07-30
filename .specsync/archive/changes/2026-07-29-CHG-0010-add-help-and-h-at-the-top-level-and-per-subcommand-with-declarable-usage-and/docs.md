---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: docs
---

# Docs

- `README.md` adds CLI discovery examples and uses `--` in wrapped-command examples.
- `docs/getting_started.md` documents `--help`, `-h`, `rune help <command>`, structured help, and
  separator-safe invocation.
- `specs/cli/cli.spec.md` records the help aliases, DSL, payloads, separator behavior, complete
  alias removal, and invocation-local state.
- `specs/pty_runner/pty_runner.spec.md` records that command help does not construct a PTY runner.
- `specs/watch/watch.spec.md` records Watch's declared help surface.
- `CHANGELOG.md` records the new discovery surface and the separator documentation correction.
