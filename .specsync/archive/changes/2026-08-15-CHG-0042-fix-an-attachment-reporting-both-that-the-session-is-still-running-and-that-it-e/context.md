---
change: CHG-0042-fix-an-attachment-reporting-both-that-the-session-is-still-running-and-that-it-e
artifact: context
---

# Context

Reported from real use, driving a grok session:

    [rune session] detached; the session is still running.
    ✗ Session ended while attached (the child or its supervisor exited).
    error: Plugin 'rune' exited with code 1

Those cannot both be true, and the exit code says the second one won. Reproduced by attaching to a
session whose child exits underneath: the output is character for character what was reported.
