---
change: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
artifact: context
---

# Context

Ranks 1 and 3 from the nine-language translation dogfood, both confirmed here
before anything was changed.

**The tail bound was a silent no-op on the output sessions exist to capture.**
It counted lines in the raw transcript, where CR is not a line break. A
full-screen TUI repaints with bare CRs and emits almost no LFs, so nothing
matched to trim and the whole transcript came back — with `truncated` and
`omitted_lines` absent, which reads as "nothing was dropped". Measured on
`linha1\rlinha2\r...linha5\r`:

    run     --tail=2   truncated=true omitted_lines=3  clean 2 lines, raw ALL 5
    session --tail=2   truncated=nil  omitted_lines=nil          all 5 lines

Both halves are the same root cause. `clean_output` has been through
`strip_ansi`, which does `tr("\r", "\n")`, and the raw has not — so rune treated
CR as a line terminator in the field it returned but not in the flag that bounds
it. A caller bounding a reply to protect a context window got the whole
transcript and no signal that the bound had not applied; one reporter measured
84,945 bytes returned identically for `--tail=3,5,8,12,20`.

**The send completion contract disagreed with its own documentation in three
places.** Two of the three are documentation defects, and it matters which:
`--settle-ms` being inert under `--wait-for-regex` is a deliberate fix, recorded
in the code, for quiet answering a regex send at 800ms while the child printed
DONE five seconds later, 3/3. Changing the code back would reintroduce a
measured bug. What was wrong was the spec listing four racing conditions, and
`--help` describing the flag as an accelerator returning "without waiting out
the settle window" — both read as though settle still applied, and callers lost
whole `--timeout-ms` windows to the difference.
