---
id: CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e
state: archived
type: bug_fix
base_commit: 1f6c2a083e7d7e48f6b8ec7ee0b0a8098eb53985
---

# Fix prompt_detected to reflect the last non-blank line of output, not any line ever seen, closing #30

## Intent

Fix prompt_detected to reflect the last non-blank line of output, not any line ever seen, closing #30

## Affected Canonical Specs

- `pty_runner`

## Acceptance Criteria

- prompt_detected in rune run's result reflects whether the last non-blank line of the captured output (before ANSI/prompt-pattern matching) looks like an interactive prompt, not whether any line anywhere in the entire run ever did; this also fixes a pre-existing gap where a --timeout kill unconditionally reported prompt_detected: false regardless of what was actually on screen when the process was killed; the incremental per-chunk accumulator threaded through read_pty_stream/consume_output_chunk/read_separate_streams/poll_ready_streams/consume_stream_chunk/append_decoded_chunk is removed since it is no longer needed; specs/pty_runner/pty_runner.spec.md documents the corrected semantics; new RSpec coverage for the last-line behavior (including the timeout case) passes; fledge lanes run verify passes.

## No-spec Rationale

Not applicable
