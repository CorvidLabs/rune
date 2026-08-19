---
change: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
artifact: tasks
---

# Tasks

- [x] Reject a non-object control request before dispatch, with the child's survival proven by its
      own heartbeat file rather than by a rune reply
- [x] Recompute state in `liveness`, sharing `resolved_state` with the send refusal
- [x] Keep `exited`/`stopped` distinguishable from `dead`
- [x] Stop the refusal contradicting itself and printing `nil`
- [x] Floor the idle ladder so label and colour change together; clamp a negative idle
- [x] Raise `MAX_CARRY_BYTES` above any producer's read size
- [x] Correct the parsers invariant to state the over-ceiling divergence
- [x] Widen `TextSanitizer` to the CSI grammar `ScreenRenderer` already uses
- [x] Verify every new test against deliberately reverted code, confirming the revert applied
