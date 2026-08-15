---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: research
---

# Research

Measured against every real transcript collected while dogfooding, raw / stripped / rendered:

| child  | raw    | `strip_ansi` | screen | render time |
|--------|--------|--------------|--------|-------------|
| grok   | 361 KB | 36.9 KB      | 1.1 KB | 26 ms       |
| claude | 163 KB | 63.2 KB      | 2.4 KB | 36 ms       |
| agy    | 11 KB  | 6.2 KB       | 3.7 KB | 5 ms        |
| bash   | 201 B  | 189 B        | 188 B  | 0 ms        |

The cooked-mode shell barely changes, which is the control: it does not repaint, so there is nothing
to collapse. The full-screen agents collapse by one to two orders of magnitude.

End to end against grok over three turns, the answer was absent from the byte stream 3/3 and present
in the rendered screen 3/3.

A soak across grok, agy, claude and bash — 12 rounds each of send/list/read/read-since plus
stop/archive/restart — reported 0 anomalies, confirming the 0.4.0 crash fix holds.
