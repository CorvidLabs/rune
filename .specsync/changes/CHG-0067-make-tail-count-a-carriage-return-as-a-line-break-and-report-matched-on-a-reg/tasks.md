---
change: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
artifact: tasks
---

# Tasks

- [x] Reproduce both ranks before changing anything
- [x] `tail_lines` counts CR/LF/CRLF and preserves terminators
- [x] `matched: false` on a regex send timeout, non-regex sends unchanged
- [x] Spec invariant 6, `docs/sessions.md` on `settled`, and the `--help` text
- [x] Four regression tests, each falsified
