---
change: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
artifact: requirements
---

# Requirements

1. A control-socket request that is valid JSON but not an object is answered with an error, and the
   supervisor and child both survive.
2. `read` and `send` report a state recomputed from real process liveness, agreeing with `list`.
3. A session whose child exited or was stopped deliberately still reports that, not `dead`.
4. The refusal for a send to a dead session neither contradicts itself nor prints Ruby's `nil`.
5. No idle label in `list` renders in two colours: the label and the threshold change together.
6. Idle time hands over between units where each stops reading naturally, floors rather than
   rounds, and clamps a negative idle to zero.
7. `MAX_CARRY_BYTES` exceeds any producer's read size, so a sequence spanning several pty reads is
   carried.
8. The parsers invariant states the over-ceiling divergence rather than denying it.
9. `TextSanitizer` strips every CSI form `ScreenRenderer` understands, without eating ordinary text
   containing colons, brackets or digits.
