---
change: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
artifact: tasks
---

# Tasks

- [x] Measure all five against ECMA-48/xterm before changing anything
- [x] Rewrite the double-width probe, which could not fail
- [x] Alternate screen buffer (1049/1047/47/1048), including reset behaviour
- [x] DECAWM, IRM, DEC Special Graphics, SO/SI
- [x] `TextSanitizer`: two-byte escapes and the full designation set
- [x] Specs, harness, and the double-width limitation recorded with its measurement
- [x] Dogfood against claude, grok, kimi and agy
