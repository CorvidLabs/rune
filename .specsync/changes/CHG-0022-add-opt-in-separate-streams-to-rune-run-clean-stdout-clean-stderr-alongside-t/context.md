---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: context
---

# Context

Issue #15: everything a wrapped command writes to stdout and stderr arrives merged in a single
`clean_output` string, with no way to tell them apart — inherent to running the child on one PTY
(there is one stream by construction). This is a real regression against the baseline rune is
meant to improve on (`subprocess.run(capture_output=True)` gives separate `stdout`/`stderr`), and
an agent triaging a failing build normally starts with "what went to stderr" — through rune, it
couldn't.

The issue offers two bars: document the merge as a Known Limitation, or add an opt-in mode that
spawns stdout on a PTY and stderr on a pipe. Per an explicit product decision made in this session,
this change implements the opt-in dual-stream mode (the deeper option), not just the doc-only
minimum.
