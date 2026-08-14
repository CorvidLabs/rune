---
change: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
artifact: plan
---

# Plan

1. Add `lib/rune/output_limiter.rb` (`Rune::OutputLimiter`, class-method style matching
   `Rune::Parsers::TextSanitizer`): `.truncate_middle(text, max_bytes)` and `.tail_lines(text, n)`,
   each returning `[result_text, omitted_count]`.
2. Require it from `lib/rune.rb` alongside the other PTY-runner support classes.
3. `PTYRunner#initialize` gains `max_output_bytes:`/`tail_lines:` keyword args (default `nil`,
   both `nil` reproduces current behavior exactly). Apply them to `clean_output`/`raw_output` in
   `#run`, right before building the `Result`, merging `truncated`/`omitted_*` into the data hash
   only when one of the options is set.
4. `RunCommand` gains a combined flag extractor alongside the existing `--timeout` one:
   `--max-output=BYTES`, `--tail=N`; validated as positive integers; mutual-exclusion checked
   before constructing `PTYRunner`.
5. Update `specs/pty_runner/pty_runner.spec.md`: Public API rows for `OutputLimiter` and the new
   `PTYRunner`/`RunCommand` options, new Invariants, Behavioral Examples, Error Cases, Change Log
   entry.
6. Tests: `spec/rune/output_limiter_spec.rb` (new), additions to `spec/rune/pty_runner_spec.rb`
   and `spec/rune/commands/run_command_spec.rb`.
7. `fledge run test`, `fledge run lint`, `fledge run spec-check`, then closing approval + accept.
