---
change: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
artifact: research
---

# Research

| fix | measurement |
|---|---|
| echo settle | 0/3 runs returned the answer before, 3/3 after |
| renderer DoS | 7 cases: RangeError, 2.9GB, non-terminating → all 0.000s |
| scroll regions | 8 of 40 rows wrong on two real captures → 0 |
| quadratic observe | 12MB turn: 67s at 100% CPU, false timeout |

The renderer was checked against **two** references, pyte and xterm.js headless. They disagreed with
rune three times and **rune was right all three** — pyte does not implement SU at all. Each
divergence was resolved against xterm's own source before anything was changed, which is why no
correct behaviour was 'fixed'.
