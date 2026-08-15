---
change: CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e
artifact: testing
---

# Testing

Three tests: the note appears after a detach, does not appear when the attachment ended underneath,
and the failure message points at `rune session list` without claiming the child exited. Two fail
against the unfixed version.

They drive `close_quietly` directly, because the property is about which message is printed on
which path, and reproducing the real thing needs a pty and a session that dies on cue — done once by
hand and recorded in research.md rather than run in CI.

366 examples, 0 failures; lint clean.
