---
change: CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim
artifact: design
---

# Design

`--grep=RE` with `--context=N` filters the reply. It runs against the *cleaned* text rather than
the raw stream, because a full-screen agent's repaint frames split words across escape sequences —
a pattern plainly visible on screen does not match the bytes, which would make the feature appear
broken exactly where it is most needed. Context windows are deduplicated so overlapping ones do not
repeat lines. An unparseable pattern returns `grep_error`; a caller's typo is not a reason to fail
a read.

The documentation corrections are the other half. `prompt_detected` was described as usually false
for agent CLIs; measured, it is false for plain text, false for a bare shell prompt, false for
`Do you want to proceed?`, and true for `❯` — so for grok it is true on essentially every read,
and it is false for precisely the dialog a caller would want it to catch. `settled` was documented
as unable to distinguish "finished" from "waiting on a human"; there is a third case, a child that
backgrounded a long command and went quiet, and that is the one that produced a false "finished"
260 seconds early in real use.
