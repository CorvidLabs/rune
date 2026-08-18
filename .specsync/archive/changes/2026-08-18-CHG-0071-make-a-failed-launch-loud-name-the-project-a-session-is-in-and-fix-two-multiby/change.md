---
id: CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby
state: archived
type: feature
base_commit: 5f4d77b08f0d96682520e66e7eeb5411ed5a5da3
---

# Make a failed launch loud, name the project a session is in, and fix two multibyte defects

## Intent

Make a failed launch loud, name the project a session is in, and fix two multibyte defects

## Affected Canonical Specs

- `session`
- `parsers`

## Acceptance Criteria

- rune session start returns status error when the command is not on PATH, while a child that exits zero immediately still succeeds. The no-such-session error names the project the session is actually in and points at a remedy that shows it. CharacterWidth gives Indic nonspacing marks no column while leaving spacing marks at one, matching wcwidth. ScreenRenderer resync searches by byte offset rather than character index, so a multi-byte head is dropped whole instead of cut mid-character. Each has tests that fail against deliberately reverted code.

## No-spec Rationale

Not applicable
