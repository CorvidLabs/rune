---
change: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
artifact: research
---

# Research

Cost of a single rotation of a 31.5MB transcript, measured directly:

| implementation | resident memory |
|----------------|-----------------|
| `readlines` plus two `JSON.parse` per line | **+229 MB** |
| streaming lines, still parsing each one | **+96 MB** |
| seek, regex, `IO.copy_stream` | **+0.1 MB** |

The middle row is the point worth keeping: streaming alone looked like the fix and was not. It would
have shipped had the measurement not been repeated.

The 45-minute two-session run that exposed this: 4176 turns, zero failures, descriptors flat at 54
throughout, and resident memory stepping from 145MB to 374MB across the rotation boundary.
