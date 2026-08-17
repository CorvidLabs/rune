---
change: CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus
artifact: context
---

# Context

Found by re-running ROADMAP.md's "known, unfixed" table against the tree instead of
trusting it. Seven of the eight were already closed; this is the one that was not.

`--max-output` and `--tail` are parsed for every session subcommand and were
applied only by `read`. Measured before the fix, against `python3 -q`:

    send (no flags)         status=ok  clean_len=4187
    send --max-output 120   status=ok  clean_len=4187   <- flag accepted, ignored
    send --tail 3           status=ok  clean_len=4187   <- same
    read --max-output 120   status=ok  clean_len=65     <- honoured here

A caller that asked for a bound was told `status: ok` and given everything. A
field report had already named why this is the worst place for the gap: "the one
call an agent makes most has no output bound."

A second inconsistency surfaced while checking the first: `rune run` refuses
`--max-output` together with `--tail`, and sessions accepted both, silently
applying whichever `bound_size` tested first.
