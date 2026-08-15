---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: requirements
---

# Requirements

1. Resident memory must not grow with total output.
2. Cursors must keep meaning the same thing: absolute byte offsets into the whole stream.
3. An in-flight send must still receive everything it produced, however long its turn runs.
4. An attaching terminal must still get its backlog.
