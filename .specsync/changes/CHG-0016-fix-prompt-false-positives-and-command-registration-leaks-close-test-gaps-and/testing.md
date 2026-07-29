---
change: CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and
artifact: testing
---

# Testing

- Unit-test every issue #11 false-positive example and retained prompt category.
- Assert `Class.new(Command) { name "probe" }` registers synchronously.
- Compare enabled TracePoint counts before and after unnamed subclass creation.
- Parse an unknown-command NDJSON envelope and assert `event == "error"`.
- Create a new explicit watch-log path and assert its permission bits equal `0600`.
- Run `fledge run test`, `fledge run lint`, `fledge spec check --strict`, and `fledge trust verify`.

## Evidence

- Focused regression set: 52 examples, 0 failures.
- Full suite before the CLI integration companion: 205 examples, 0 failures.
- CLI/renderer integration set after CHG-0017: 35 examples, 0 failures.
- RuboCop: 50 files, 0 offenses.
- Bundler 4 and Bundler 2.4/Ruby 3.1 both accept the tracked lockfile.
- Strict SpecSync: 4 specs, 0 errors, 0 warnings.
