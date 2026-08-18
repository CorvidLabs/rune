---
id: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
state: archived
type: feature
base_commit: 8c9055be7093551caf654679a1f8ebb51357de50
---

# Make --tail count a carriage return as a line break, and report matched on a regex send's timeout

## Intent

Make --tail count a carriage return as a line break, and report matched on a regex send's timeout

## Affected Canonical Specs

- `session`
- `pty_runner`

## Acceptance Criteria

- The tail bound counts CR, LF and CRLF as line breaks, so it bounds a full-screen TUI's repaint output instead of silently returning everything with truncated and omitted_lines absent. rune run bounds raw_output as well as clean_output, which it did not when the raw stream had no LFs. A regex send reports matched false when it times out, as its own comment always claimed. The documentation saying a regex send races the settle window is corrected in the spec, in docs/sessions.md and in help, and settled is defined as the wait being answered rather than the child going quiet. Four regression tests, each falsified against deliberately unfixed code.

## No-spec Rationale

Not applicable
