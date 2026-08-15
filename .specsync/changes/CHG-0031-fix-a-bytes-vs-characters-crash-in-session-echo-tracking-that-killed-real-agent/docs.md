---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: docs
---

# Docs

`--settle-ms` help text now states the 3000ms default. The session spec's Known Limitations carries
the measured settle numbers, the continuously-animating-child case, and the fact that a reply is a
byte stream rather than a rendered screen.
