---
change: CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0
artifact: research
---

# Research

grok supplied a table of inputs with the xterm and ECMA-48 results for each. All eighteen cases
derived from it now match a real terminal, including the four last-column cases that previously
matched neither model.

Teardown was measured before and after against a live session stopped mid-send:

| | before | after |
|---|---|---|
| in-flight sender | `error: supervisor closed the connection without replying` | `ok`, its captured output, `supervisor_exited: true` |
| control.sock | left on disk | removed |
| exit_code | `nil` | `137` |

Real transcripts still render correctly after the renderer rewrite, including a 4.6MB one that
collapses to 1.6KB without hanging.
