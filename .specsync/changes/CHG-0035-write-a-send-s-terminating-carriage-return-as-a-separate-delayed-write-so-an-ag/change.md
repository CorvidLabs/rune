---
id: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
state: accepted
type: feature
base_commit: 9fcf83cfeb4f28ace4dfeacbae29b4afc20e72b7
---

# Write a send's terminating carriage return as a separate delayed write, so an agent TUI submits the prompt instead of treating it as a pasted newline

## Intent

Write a send's terminating carriage return as a separate delayed write, so an agent TUI submits the prompt instead of treating it as a pasted newline

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A send writes the text and its terminating carriage return as two separate writes, with the terminator delayed until the text has drained, so a raw-mode child receives them in two reads rather than one. Verified against Claude Code across seven input lengths from 61 to 262 characters: before the fix only 61 submitted, after it all seven do, with no regression on grok or agy which also pass 7/7. A regression test asserts the carriage return arrives as a read of its own and never in the same read as the text, and fails against the unfixed supervisor. An outstanding terminator is flushed immediately when another send arrives, preserving order. --no-newline still sends no terminator. Full suite and lint pass.

## No-spec Rationale

Not applicable
