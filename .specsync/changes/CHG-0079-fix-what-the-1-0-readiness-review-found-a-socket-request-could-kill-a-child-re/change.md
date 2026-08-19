---
id: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
state: accepted
type: bug_fix
base_commit: a95f912fde324b737bdcba2496d530b753e5204f
---

# Fix what the 1.0 readiness review found: a socket request could kill a child, read reported dead sessions as running, and two parsers disagreed about what an escape is

## Intent

Fix what the 1.0 readiness review found: a socket request could kill a child, read reported dead sessions as running, and two parsers disagreed about what an escape is

## Affected Canonical Specs

- `session`
- `parsers`

## Acceptance Criteria

- A control-socket request that is valid JSON but not an object is answered with an error and leaves the supervisor and child alive (measured 7/7, previously 5/5 such payloads killed both). session read and send report a state recomputed from process liveness, so a SIGKILLed supervisor reads as dead on every verb rather than running on read and dead on list, and the refusal message no longer contradicts itself or prints Ruby's nil. In list, no idle label renders in two colours: the threshold and the label change at the same instant, an hour reads 1.0h rather than 60m, ninety seconds reads 1m rather than 2m, and a negative idle from a backward clock step is clamped to zero. MAX_CARRY_BYTES is larger than any producer's read size so a sequence spanning several pty reads still carries, with the residual over-ceiling divergence stated in the invariant rather than denied by it. TextSanitizer strips the CSI forms ScreenRenderer already understood, so colon-form truecolour SGR and DECSCUSR no longer survive into clean_output, --grep and last_line. Every new test fails when its arm is reverted.

## No-spec Rationale

Not applicable
