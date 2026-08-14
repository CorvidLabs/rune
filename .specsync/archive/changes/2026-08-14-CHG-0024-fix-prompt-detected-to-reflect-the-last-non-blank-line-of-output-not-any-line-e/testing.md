---
change: CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e
artifact: testing
---

# Testing

- A command that prints a prompt-shaped line mid-run and then more ordinary output afterward:
  `prompt_detected` is `false` (regression guard for the exact false-positive issue #30 reports).
- A command whose last line of output is genuinely prompt-shaped (nothing follows):
  `prompt_detected` is `true`.
- A command with no output at all, or only blank lines: `prompt_detected` is `false`, no crash.
- The existing `<placeholder>`-line false-positive regression test (issue #11) still passes
  unchanged under the new last-line semantics.
- A `--timeout` kill where the last line before the kill was prompt-shaped: `prompt_detected` is
  now `true` (previously hardcoded `false` regardless of content — direct regression test for the
  latent bug found during this change).
- Evidence to be filled in after implementation: `fledge run test`, `fledge run lint`,
  `fledge run spec-check` results.
