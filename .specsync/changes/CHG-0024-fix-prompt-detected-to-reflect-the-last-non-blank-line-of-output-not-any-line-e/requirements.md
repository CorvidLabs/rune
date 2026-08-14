---
change: CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e
artifact: requirements
---

# Requirements

- `data[:prompt_detected]` is `true` iff the last non-blank line of the captured output (ANSI
  stripped) matches `PromptDetector`'s prompt patterns — not "any line in the entire run."
- This holds identically for a natural exit, a `PTY::ChildExited` short-circuit, and a
  `--timeout` kill (previously hardcoded `false` on timeout regardless of actual content).
- No behavior change to `PromptDetector` itself, `Script`'s `wait_for` matching, or any other
  field in the result data — this is scoped to how `prompt_detected` alone is computed.
- The per-chunk accumulator threaded through `read_pty_stream`, `consume_output_chunk`,
  `read_separate_streams`, `poll_ready_streams`, `consume_stream_chunk`, and
  `append_decoded_chunk` is removed; those methods return to being pure output-capture code.
