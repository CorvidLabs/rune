---
id: CHG-0057-fix-max-output-fabricating-text-at-the-cut-and-refuse-mistyped-flags-instead-o
state: draft
type: bug_fix
base_commit: 66abd03eef2fee1be7f20f9762d3a471dad9089d
---

# Fix --max-output fabricating text at the cut and refuse mistyped flags instead of typing or exec-ing them

## Intent

Fix --max-output fabricating text at the cut and refuse mistyped flags instead of typing or exec-ing them

## Affected Canonical Specs

- `session`
- `pty_runner`
- `cli`

## Acceptance Criteria

- A --max-output result carries a [rune] ==== N bytes omitted by --max-output ==== line between head and tail, and neither cut lands inside an escape sequence: censused over all 14,029 cut points of a real vim transcript, 2,306 head cuts and 4,399 tail cuts fell inside a sequence and all emitted the orphan, and now none do while the marker survives strip_ansi at all 14,029 (previously 0). An unparseable --grep returns empty output with grep_error and no grep_matches, matching what a valid non-matching pattern returns. rune session send --name=x --settle_ms 500 'echo HELLO' and rune run --tiemout=5 -- echo hi both fail with Unknown option instead of status ok, while rune session start --name=x claude --resume, rune run cargo clippy --tests, send -- --settle_ms and --- section --- are unchanged. bundle exec rspec (435 examples) and rubocop both pass.

## No-spec Rationale

Not applicable
