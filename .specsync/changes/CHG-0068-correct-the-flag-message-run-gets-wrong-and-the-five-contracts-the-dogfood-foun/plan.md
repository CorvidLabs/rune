---
change: CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun
artifact: plan
---

# Plan

Step 1 is the only code: `unknown_flag_error` branches when the token names a
flag `run` owns, into `INLINE_VALUE_ERROR`. `VALUE_FLAGS` derives from
`FLAG_PATTERNS`, because a hand-maintained list is exactly what let `--context`
ship accepted-and-ignored.

Steps 2-5 are documentation, sequenced so the three findings that collide on the
pty_runner surface are done in one pass, and the two that collide on the session
surface in another.

Deliberately NOT fixed, each because the fix measured worse:
- rank4 as code — deriving clean from bounded raw cuts readable payload by the
  ANSI fraction on every colour-emitting child, against the flag`s purpose.
- rank6 as code — grepping the screen loses scrollback, which is why `--grep`
  exists; measured, 39 of 200 lines were on screen.
- rank9 as code — making it reconcile means discarding the split character`s
  fragment, contradicting the scrub invariant; redefining the count changes the
  marker`s length and could flip `truncated` for callers who changed nothing.
- rank10 as code — rendering only the bounded bytes paints a discarded frame and
  rune`s own elision marker into the child`s screen, losing 9 of 10 answers.
