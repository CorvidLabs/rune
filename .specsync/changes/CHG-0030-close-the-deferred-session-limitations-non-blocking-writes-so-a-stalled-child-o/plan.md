---
artifact: plan
---

# plan

See design.md. Four documented limitations closed, each pinned by a regression test:
non-blocking writes, terminal-size propagation on attach, idle-connection reaping, and a
per-name start lock. Plus one discovery documented rather than fixed: the 1024-byte
MAX_CANON limit on a cooked-mode child's input.
