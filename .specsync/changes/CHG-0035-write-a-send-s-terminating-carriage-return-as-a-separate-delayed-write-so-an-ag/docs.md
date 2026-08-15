---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: docs
---

# Docs

The session spec's terminator invariant now states that the carriage return is a separate delayed
write, why a TUI would otherwise read it as a pasted newline, and the measured length boundary.
