---
change: CHG-0073-record-that-wait-for-regex-can-match-a-prior-turn-redraw-and-bring-the-1-0-ro
artifact: design
---

# Design

No code change to the match path. A heuristic here is the same class of mistake as the four
settle rules: each candidate wins the reprint case and loses a case that is already in the
suite or in real use.

The occurrence-vs-string problem is what a retained per-session `Screen` is for. Until that
exists, the API should not imply `--wait-for-regex` can tell a reprint from a new answer.
The one example added to the suite is the workaround (unique-per-turn pattern), so a later
fix cannot lose it.
