---
change: CHG-0024-fix-prompt-detected-to-reflect-the-last-non-blank-line-of-output-not-any-line-e
artifact: context
---

# Context

Issue #30, found via real dogfooding (rune driving `grok` as an unattended sub-agent for four
~10-23 minute sessions): `prompt_detected` was `true` on every single run, providing zero
discriminating signal. `PTYRunner` currently OR-accumulates prompt-pattern matches across every
line of the *entire* captured run. For a long, TUI-heavy session that's nearly guaranteed to
contain at least one line that shape-matches a prompt as ordinary UI chrome (a persistent input
box, a `? ` query line) even though the process never actually blocked.

`rune run`'s result is only ever read after the wrapped process has already exited or been killed
by `--timeout` — so "did a prompt-shaped line ever appear" was never the useful question. "Was the
last thing on screen a prompt, with nothing after it" is: if a process is genuinely stuck waiting
for input, by definition nothing else arrives after that line. Checking only the last non-blank
line of the finished buffer captures exactly that, with no timing/idle-gap logic needed (deliberately
avoided — timing-based checks are a known flakiness risk in this codebase's own test suite).

This also fixes a related latent bug found while implementing: on an actual `--timeout` kill, the
accumulator variable never received its final value (`Timeout::Error` interrupts execution inside
`spawn_for_mode`, before the assignment that would set it completes), so `prompt_detected` was
unconditionally `false` on every timeout regardless of what was actually on screen — the exact case
where this field is most useful. The new implementation computes the answer directly from whatever
`raw_output` was captured up to the kill point, fixing this for free.
