---
id: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
state: accepted
type: feature
base_commit: ad76e2237bb8215f77d4cd7bb8358cc6083a61f2
---

# Guard the flags watch was executing, and bound the two fields max-output was not

## Intent

Guard the flags watch was executing, and bound the two fields max-output was not

## Affected Canonical Specs

- `watch`
- `pty_runner`
- `session`
- `cli`

## Acceptance Criteria

- rune watch refuses a flag-shaped token it does not own instead of executing it as the command, sharing run's guard rather than copying it. rune session read honours --since when --grep is given, searching the slice rather than the whole transcript. max-output and tail bound clean_stdout and clean_stderr as well as the merged fields. Each fix has tests that fail against deliberately reverted code, including a drift guard for watch's flag list. Export documentation follows the two constants and one method that moved from RunCommand to Command.

## No-spec Rationale

Not applicable
