---
change: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
artifact: context
---

# Context

Three defects that surfaced during the triage of the translation dogfood but were
out of that PR`s scope. Each was verified here before being planned.

**watch executed the flags it did not recognise.** Anything flag-shaped stayed in
the argv and became the command. My first probe of this was worthless: a non-tty
run refuses on "stdin is not a TTY" before parsing anything, so the refusal was
the TTY check and proved nothing. Driven through a real `PTY.spawn`,
`rune watch --timeout 5 -- echo hi` exited **127 with the child never running**.
`run` has guarded this since it grew flags. watch never did, which made it the
worse of the two — run at least says something.

**`--grep` ignored `--since`.** `filter` was handed the sliced text and then
called `transcript.grep`, which searched `@text`. Measured: a read from a cursor
recorded after the first line still returned that line, and `grep_matches`
counted it.

**`--max-output` did not bound the separate streams.** A 200-byte budget returned
10,506 bytes across four fields, because only the merged pair went through
`apply_output_limit`.
