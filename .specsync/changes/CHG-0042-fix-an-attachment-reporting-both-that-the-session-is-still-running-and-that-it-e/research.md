---
change: CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e
artifact: research
---

# Research

Both paths, end to end over a pty:

| | exit | still-running note | ended message |
|---|------|--------------------|---------------|
| deliberate detach | 0 | yes | no |
| session ends underneath | 1 | no | yes |

Neither path now produces both.

Three harness mistakes preceded the reproduction and are worth recording, since each produced a
confident wrong answer: `PTY.spawn` ignores a `chdir:` option, so the first attempt attached from
a different project scope and reported "No such session"; the block form of `PTY.spawn` swallowed
the exit status; and a substring check for "still running" matched the attach hint rather than the
note, which made a fixed run look broken.
