---
change: CHG-0046-rotate-a-session-transcript-without-reading-it-seek-to-the-cut-and-copy-the-tai
artifact: requirements
---

# Requirements

1. A rotation must not measurably increase resident memory.
2. The accounting must stay exact: dropped plus retained equals everything written.
3. Cursors must keep their meaning across a rotation.
