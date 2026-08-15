---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: testing
---

# Testing

No new behaviour, so the test is that nothing changed: 360 examples pass, including the regression
tests for every defect this logic has had — the byte-versus-character echo crash, the regex matching
its own echo, the catastrophic-backtracking bound, the settle-before-submission rule, and the
multibyte grace window.

The three echo tests that reached into the supervisor's privates now construct a `PendingSend`
directly, which is the point of the extraction: they no longer need a supervisor to ask a question
about a send.
