---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: research
---

# Research

`child_busy` against a child printing for two seconds then stopping:

| when | `child_busy` | `idle_ms` |
|------|--------------|-----------|
| while printing | true | 61 |
| after finishing | false | 3268 |

The reported `exit_code` behaviour is correct and not a defect: eight one-shot dispatches returned
0 because the wrapped process exited 0 in each case. `124` remains the one value worth branching
on, since it means rune killed the process on `--timeout`.
