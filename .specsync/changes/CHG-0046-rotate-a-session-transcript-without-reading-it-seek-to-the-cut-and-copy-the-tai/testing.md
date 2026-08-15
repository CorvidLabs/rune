---
change: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
artifact: testing
---

# Testing

The existing four disk tests still pass, and one of them had to be fixed rather than the code: it
drove `log_event` directly, which bypasses the transcript window the accounting reads from, so it
passed against the broken version and failed against the correct one. It now uses `append`, the
real path.

The memory figure itself is measured rather than asserted, in research.md — a rotation costs 0.1MB,
against 229MB and 96MB for the two earlier versions.
