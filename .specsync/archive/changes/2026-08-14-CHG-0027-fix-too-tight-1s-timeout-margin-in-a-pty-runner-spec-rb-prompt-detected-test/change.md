---
id: CHG-0027-fix-too-tight-1s-timeout-margin-in-a-pty-runner-spec-rb-prompt-detected-test
state: archived
type: bug_fix
base_commit: 314e1c26587812d9963ae24214386d629def3b5e
---

# Fix too-tight 1s timeout margin in a pty_runner_spec.rb prompt_detected test

## Intent

Fix too-tight 1s timeout margin in a pty_runner_spec.rb prompt_detected test

## Affected Canonical Specs

- None

## Acceptance Criteria

- spec/rune/pty_runner_spec.rb's --timeout kill prompt_detected test uses timeout_seconds: 3 (not 1) with a matching longer child sleep, resolving a reproducible-under-load flake; fledge run test passes; no library or contract change.

## No-spec Rationale

Test-only fix (timeout_seconds: 1 -> 3, matching this file's own existing pattern for the same real-system-load risk); no library code, public API, or canonical contract change.
