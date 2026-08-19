---
change: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
artifact: docs
---

# Docs

`specs/parsers/parsers.spec.md` invariant 11a is rewritten. It previously asserted the chunked
render always equals the one-shot render, and that past the ceiling the bytes "are dropped, which is
what a one-shot render already did with them". Both halves were false. It now scopes the
equivalence to sequences within `MAX_CARRY_BYTES`, states that the over-ceiling case prints the
payload where one-shot does not, records why the ceiling was moved off `READ_CHUNK`, explains why
discard-until-terminator was rejected, and notes that the instance path assumes decoded input.

`specs/session/session.spec.md` records that `read` and `send` recompute state rather than reporting
the recorded claim, and that a non-object control request is refused rather than dispatched.

No user-facing documentation changes here. The guide's stale `start` contract and the roadmap's
mixing of solved and unsolved items are real and are being corrected separately, so that this change
stays a code change.
