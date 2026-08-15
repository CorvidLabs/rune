---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: requirements
---

# Requirements

1. The transcript file must stay under a ceiling however long the session runs.
2. Recent output must survive, since that is what `--since` and an attach backlog reach for.
3. Rotation must not make a cursor lie: a cursor keeps naming the same position in the stream.
4. A caller asking for output that has been dropped must be told, not quietly given less.
