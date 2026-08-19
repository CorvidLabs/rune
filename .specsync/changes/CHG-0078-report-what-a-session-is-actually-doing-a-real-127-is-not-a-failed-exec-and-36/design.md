---
change: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
artifact: design
---

# Design

## Recording the fact instead of inferring it

The exit status cannot distinguish "never executed" from "executed and chose to exit 127", because
both are the number 127. Any test built on the status alone is therefore guessing, and it guessed
wrong 7 times in 12.

The supervisor is the only place that can know: `PTY.spawn` raising `ENOENT`/`EACCES` happens before
the child exists, so reaching that rescue *is* the fact. `finish` takes a `launch_failed:` keyword
and writes the field only on that path.

Written only when true, never as `false`. A reader that sees no field is looking at a child that
ran, which is also exactly how meta from an older version reads — so the field needs no migration.

## Not building a stuck-detector

The tempting fix for the second defect is to detect the approval prompt and report "blocked". That
is a heuristic over arbitrary TUI output, and this repo has measured and rejected four heuristics of
that shape on the adjacent settle problem. `PromptDetector` is deliberately conservative and returns
false for exactly the agent REPLs this module exists to drive.

So the change makes an existing *fact* legible and classifies nothing. `idle_ms` was always correct;
it was rendered in a unit that stopped being readable an hour in, and in a colour that says ignore
me. The threshold picks a colour and carries no claim about what the session is doing.

The honest limit is recorded rather than papered over: a child that repaints a spinner while blocked
holds `idle_ms` near zero, so this makes the silent stall visible and does nothing for the noisy one.
