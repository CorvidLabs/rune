---
change: CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby
artifact: plan
---

# Plan

Only exit 127 fails the launch. Any prompt exit would break every short-lived
child, and 127 is specifically the shell reporting a command it could not find.

The scoping hint costs one directory listing per project and is rescued, because
a best-effort hint must never turn a clear error into a crash.

The width fix is the Mn/Me subset, not every Indic mark. The report framed it as
"one column per codepoint", which overstates it: U+093F is a *spacing* mark and
legitimately takes a column, so zeroing everything Indic would be as wrong in the
other direction. `हिन्दी` is five columns here and in xterm, not the three a
shaping engine draws — this follows wcwidth and does not try to settle shaping.

`resync` searches a binary copy, because `byteindex` arrived in Ruby 3.2 and this
gem supports 3.0.
