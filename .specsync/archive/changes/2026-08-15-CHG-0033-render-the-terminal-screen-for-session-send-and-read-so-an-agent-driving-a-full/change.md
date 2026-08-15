---
id: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
state: archived
type: feature
base_commit: 9176cf741f0d98a663530d6d0fac1e361ae40be1
---

# Render the terminal screen for session send and read, so an agent driving a full-screen agent can find the answer instead of searching every repaint frame

## Intent

Render the terminal screen for session send and read, so an agent driving a full-screen agent can find the answer instead of searching every repaint frame

## Affected Canonical Specs

- `session`
- `parsers`
- `cli`

## Acceptance Criteria

- rune session read --screen and rune session send --screen return a Must be connected to a terminal. field holding the rendered terminal, and omit it entirely when not passed so the default result shape is unchanged. Parsers::ScreenRenderer replays cursor motion, erasing and line discipline rather than deleting escapes as TextSanitizer does, never fails to consume input, tolerates invalid UTF-8, and bounds work by rendering only the transcript tail. Verified end to end against grok: the answer was absent from the byte stream 3/3 turns and present in the rendered screen 3/3 turns. Full suite and lint pass.

## No-spec Rationale

Not applicable
