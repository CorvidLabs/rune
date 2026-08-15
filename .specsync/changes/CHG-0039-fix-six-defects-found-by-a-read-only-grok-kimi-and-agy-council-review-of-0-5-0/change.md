---
id: CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0
state: accepted
type: feature
base_commit: e70d8d35af9520a34f5302b784ce15f5fef13b64
---

# Fix six defects found by a read-only grok, kimi and agy council review of 0.5.0: renderer escapes and last-column cursor, a send accepted mid-delivery, a send settled before submission, stop killing before teardown, a false exit code, and a skipped process-group kill

## Intent

Fix six defects found by a read-only grok, kimi and agy council review of 0.5.0: renderer escapes and last-column cursor, a send accepted mid-delivery, a send settled before submission, stop killing before teardown, a false exit code, and a skipped process-group kill

## Affected Canonical Specs

- `parsers`
- `session`

## Acceptance Criteria

- ScreenRenderer obeys ESC D/E/M, cursor save and restore in both DECSC/DECRC and CSI forms, VPA, the insert/delete/erase-character family, line insert/delete/scroll, and vertical tab and form feed as motion; the last-column cursor follows xterm deferred wrap. A send is refused while a previous send's text is still going out, and nothing settles a send whose terminator has not gone out. stop waits for the cooperative shutdown before force-killing, so an in-flight send gets its captured output and the control socket is removed; the recorded exit code reflects the signal; and a process-group kill is not gated on the leader being alive. Regression tests for all of it, verified against the unfixed code. Full suite and lint pass.

## No-spec Rationale

Not applicable
