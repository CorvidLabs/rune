---
change: CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors
artifact: research
---

# Research

| fix | measured |
|---|---|
| regex-path quadratic | 12MB: 90.5s timing out -> 0.91s matched |
| default-path quadratic | 48MB: 104.53s -> 3.88s |
| argv exec fidelity | ran the wrong binary at `status: ok` -> execs the named file |
| screen geometry | 29 of 30 rendered rows wrong -> 0 of 30 |
| render window | 256KB rendered 1782 bytes of screen; 512KB renders 1990 |
| cursors across a gap | 48,000 bytes replayed as new -> 0 |
| submit delay | kimi never submitted, 3/3 -> all three agent CLIs submit |
| `--max-output` | returned 251 bytes for a 210-byte input -> never exceeds input |

Oracles: pyte, xterm.js headless and GNU screen. All three have been wrong against rune at least once,
which is why disagreements were resolved against ECMA-48 and xterm's own source rather than by vote.
