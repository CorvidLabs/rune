---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: requirements
---

# Requirements

1. A caller must be able to ask whether the child is producing output without parsing its UI.
2. It must work for a stopped session as well as a live one.
3. `exit_code` must be documented as what it is, without renaming it and breaking every caller.
4. The busy flag must not overclaim: printing is not the same as working.
