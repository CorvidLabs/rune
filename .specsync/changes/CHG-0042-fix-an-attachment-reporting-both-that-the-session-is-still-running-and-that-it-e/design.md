---
change: CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e
artifact: design
---

# Design

`close_quietly` printed the note whenever an attachment had been established — its comment called
that "deliberately unconditional" — so it fired on every exit path including the failure one. It
now prints only when the human detached, which the pump already reports and which is kept as
`@detached`.

The failure message no longer asserts a cause. An attachment can tell that output stopped; it cannot
distinguish a child that exited, a supervisor that was stopped, and an attachment dropped for not
keeping up. It says what it knows and points at `rune session list`, which can answer the rest.
