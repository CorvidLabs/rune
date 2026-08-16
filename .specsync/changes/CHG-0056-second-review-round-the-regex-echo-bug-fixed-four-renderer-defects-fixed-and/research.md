---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: research
---

# Research

| case | before | after |
|---|---|---|
| `--wait-for-regex` vs `python3 -q` | matched the echo at 0.22s, 4/4 | waits for real output, 8.2s, 3/3 |
| `--settle-ms` vs `bash -i` | 0/3 | 3/3, wrapped inputs included |
| `--settle-ms` vs `irb`/`python3` | 0/3 | **still 0/3** — documented, not narrowed |

Rejected with measurements: rendering the stream and locating the echo on screen (12/18 against a
10/18 baseline, and the most expensive option tried); ANSI-strip only (12/18); subsequence location
(13/18, and unsound — a greedy subsequence ended 59 characters before the echo's real end).

pyte disagreed once more and was wrong again: `\e[<u` is a well-formed CSI, so it must be consumed
whole, and pyte prints the `u`. That is the fourth such case in this project.
