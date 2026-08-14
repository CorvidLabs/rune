---
change: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
artifact: tasks
---

# Tasks

- [x] Add `Rune::OutputLimiter` with `.truncate_middle(text, max_bytes)` and `.tail_lines(text, n)`.
- [x] Wire `PTYRunner` to accept `max_output_bytes:`/`tail_lines:` and apply them to both
      `clean_output` and `raw_output` after capture, adding `truncated`/`omitted_bytes` or
      `truncated`/`omitted_lines` to the result data only when one of the flags is used.
- [x] Add `--max-output=BYTES` and `--tail=N` to `RunCommand`, validated as positive integers,
      mutually exclusive, recognized only before a `--` separator (matching `--timeout`).
- [x] Update `specs/pty_runner/pty_runner.spec.md` (Public API, Invariants, Behavioral Examples,
      Error Cases, Change Log).
- [x] Add RSpec coverage: `OutputLimiter` unit tests, `PTYRunner` integration tests (a real chatty
      command bounded by each flag), `RunCommand` flag-parsing tests.
- [x] Run `fledge run test`, `fledge run lint`, `fledge run spec-check`.
