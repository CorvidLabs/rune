---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: docs
---

# Docs

The getting-started guide states plainly that `exit_code` answers whether the process ended, not
whether the work succeeded, with the eight-zero-exits case that prompted it and the `124` exception.
The session guide documents `child_busy` and `idle_ms` next to the other reply fields, including
that a backgrounded command reports false.
