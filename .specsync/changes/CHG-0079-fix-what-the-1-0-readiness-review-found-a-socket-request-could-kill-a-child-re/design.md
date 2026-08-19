---
change: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
artifact: design
---

# Design

## Reject early rather than rescue late

The socket fix is a type guard before dispatch, not another `rescue`. The failure was not that an
exception escaped — it was that a non-object reached code written for a Hash. Catching `TypeError`
around `dispatch` would also swallow genuine bugs inside the ops.

## One source of truth for state

`resolved_state` is extracted and used by both `liveness` and the send refusal, so the three verbs
cannot drift apart again. `describe` already had the logic and the comment forbidding the other
behaviour; the fix is to stop having two answers to one question.

## Floor, don't round

The colour boundary and the label boundary have to be the same instant, or the highlight is
unexplainable. Flooring achieves that without a second threshold to keep in sync — the label changes
exactly when the underlying value crosses, so any threshold placed on a unit boundary is consistent
by construction.

## A ceiling that is honest rather than one that is correct

No finite `MAX_CARRY_BYTES` can be correct: OSC 52 and iTerm2 inline images are unbounded. The
options were a bigger number, a discard-until-terminator state, or unbounded memory. Discarding was
rejected because it loses the case actually served today — `tail` hands the renderer a window that
regularly begins inside a sequence whose terminator is off the front, and a discard state would
swallow the rest of the screen rather than a few KB. So: a number far above any producer's read
size, and an invariant that states what still fails.

## Widen the sanitizer to the grammar the renderer already uses

Not a new pattern — the same ECMA-48 shape `ScreenRenderer::CSI` was already corrected to. Copying
the grammar rather than inventing one is what keeps the two from disagreeing a third time.
