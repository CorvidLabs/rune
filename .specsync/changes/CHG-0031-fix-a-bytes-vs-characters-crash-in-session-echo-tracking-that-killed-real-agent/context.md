---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: context
---

# Context

`rune session` was validated by unit tests and three rounds of independent agent review, all of
which ran against synthetic children or read the code. Driving a real agent CLI in a loop found
something none of them did: the supervisor dies, reproducibly, within two to four turns, taking the
agent process with it.

It also died invisibly. `meta.json` still said `state: running` with no exit code, no `exit` event
was written to the transcript, and `supervisor.log` — which is the supervisor's stderr — was empty.
Every later command reported a session that was not there, and nothing anywhere named the cause.
Diagnosing the crash required fixing that blindness first.

Separately, the settle window's 800ms default had never been measured against a real agent. The
spec recorded "settle is a heuristic" and warned about truncated answers, which turns out to
describe the wrong failure.
