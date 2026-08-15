---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: research
---

# Research

Two measurements against real agent CLIs, not synthetic children.

**Crash.** Driving agy through repeated tool-calling turns killed the supervisor at round 2, 4 and 4
in three consecutive runs. After the fix it survives 12/12 rounds. The backtrace that identified the
cause was only available once the supervisor could report its own death.

**Settle.** Claude Code, 27 turns: three task shapes (single burst, one tool call, three sequential
tool calls) x three trials x three settle windows. The reply was the answer to the question actually
asked in 5/9 at 800ms, 8/9 at 3000ms, 8/9 at 6000ms. At 800ms the failures were not truncated
answers — they were the previous turn's answer, returned whole and well-formed. 6000ms bought
nothing over 3000ms and cost 2.5s per call.

Also observed: grok's spinner runs for the whole turn, so byte silence genuinely means the turn
ended there; and a settled reply is a byte stream, not a rendered screen — a 13-character answer
arrives inside roughly 16KB of repaints with the answer split across them.
