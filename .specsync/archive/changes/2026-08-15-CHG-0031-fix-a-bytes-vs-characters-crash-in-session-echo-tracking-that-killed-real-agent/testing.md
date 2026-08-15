---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: testing
---

# Testing

Unit coverage pins each fix directly: `echo_still_arriving?` does not raise on a multibyte slice and
reports a non-echo multibyte slice correctly; `beyond_echo` strips exactly a non-ASCII echo; a
crashed supervisor writes a `crash` event and leaves the session `exited` with code 70; a send into
a still-talking child reports `busy_at_send: true` and one into a quiet child reports false.

The crash fix was additionally verified end-to-end against the real agent CLI that exposed it: agy
died at round 2-4 in three runs before, and survives 12/12 rounds after.

317 examples, 0 failures; lint clean.
