---
id: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
state: archived
type: feature
base_commit: 763fcc233e57913c80e43300d4a54e6931ffdcb0
---

# Fix a bytes-vs-characters crash in session echo tracking that killed real agent sessions, make a dying supervisor record why instead of leaving the session marked running, and raise the send settle default from 800ms to 3000ms on measurement

## Intent

Fix a bytes-vs-characters crash in session echo tracking that killed real agent sessions, make a dying supervisor record why instead of leaving the session marked running, and raise the send settle default from 800ms to 3000ms on measurement

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- Driving a real agent CLI (agy) through repeated turns no longer kills the session: 12 consecutive turns survive where the supervisor previously died within 2-4, three runs out of three. echo_still_arriving? and beyond_echo count characters throughout, so multibyte output inside the echo grace window cannot raise and a non-ASCII prompt cannot eat the first characters of the reply. A supervisor that dies for any reason logs a crash event to the transcript and to stderr and finishes the session with exit code 70, so meta.json never stays 'running' with no exit code. The send settle window defaults to 3000ms, and a send issued while the child was still producing output reports busy_at_send: true. Full suite and lint pass.

## No-spec Rationale

Not applicable
