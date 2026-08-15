---
change: CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic
artifact: research
---

# Research

|        | window | 0.4.0 (confounded) | corrected | latency |
|--------|--------|--------------------|-----------|---------|
| claude | 800ms  | 5/9                | **9/9**   | 2.6-4.2s |
| claude | 3000ms | 8/9                | **9/9**   | 4.7-7.6s |
| claude | 6000ms | 8/9                | **9/9**   | 7.7-17.4s |
| grok   | 800ms  | 1/6                | **9/9**   | 8.7s avg |
| grok   | 3000ms | 4/6                | **9/9**   | 16.8s avg |

agy was excluded rather than reported: it became blocked on a tool-permission dialog partway through
and every later prompt queued behind it, which produced the impossible result of 5/9 at 800ms and
0/9 at 3000ms. A longer window cannot be worse than a shorter one, and that impossibility is what
identified the run as invalid rather than as evidence.
