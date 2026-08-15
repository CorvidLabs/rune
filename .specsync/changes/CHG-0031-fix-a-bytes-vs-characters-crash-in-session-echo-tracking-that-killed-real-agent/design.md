---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: design
---

# Design

**Characters throughout.** `String#index`, `String#[]` and `start_with?` are all character-based.
Both call sites now use `String#length`, never `bytesize`. Byte offsets remain correct where they
belong — transcript cursors and `byteslice`, which index a byte stream.

**Crash reporting.** `run` gains a `rescue StandardError` that logs a `crash` event to the
transcript with class, message and backtrace, writes the same to stderr, and finishes with exit code
70 (sysexits EX_SOFTWARE — an internal fault, distinct from any status the child could return).
Teardown additionally finishes the session if `finish` never ran, so no path can leave `meta.json`
claiming the session is running.

**Settle default.** Raised 800ms to 3000ms on measurement. The residual failure — the previous
turn's answer, because that turn was still arriving when the next send landed — is reported as
`busy_at_send: true` rather than prevented. Preventing it means deferring the write until the child
is quiet, which needs another deferred state in an event loop that three review rounds have already
shown is hard to get right; reporting costs one comparison.
