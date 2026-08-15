---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: context
---

# Context

The last two items from a day of field use driving grok through rune.

The caller had no structured way to ask whether the child was still working, so was grepping the
callee's own rendered UI for the string "command still running". That is presentation, not API, and
it breaks the first time the wording changes.

Separately, all eight of their one-shot dispatches returned `exit_code: 0`, including runs whose
conclusions they later had to correct. The field is behaving correctly and the documentation never
said what it means.
