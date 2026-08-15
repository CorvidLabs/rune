---
change: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
artifact: context
---

# Context

Found by running the scenario a user asked about — two agents talking through rune for a long time —
rather than by reading code. Nothing had been measured beyond a few minutes.

Over 45 minutes and 4176 turns, resident memory sat around 145MB until the transcript reached its
ceiling, then jumped to 374MB the instant the first rotation ran, and afterwards climbed twice as
fast as before. Correctness never wavered — zero failures, descriptors flat — but the rotation added
two days earlier to bound the disk had become the largest single consumer of memory in the system.

The bug was mine, introduced by the change that bounded the transcript on disk.
