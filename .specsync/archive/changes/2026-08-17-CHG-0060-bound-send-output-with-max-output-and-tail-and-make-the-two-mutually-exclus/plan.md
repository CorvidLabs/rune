---
change: CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus
artifact: plan
---

# Plan

`exchange` takes the parsed `options` and routes the reply through
`bounded_output`, which wraps the existing `with_clean_output`.

`bounded_output` bounds `output` and re-derives `clean_output` from the result,
matching `read_payload`. The alternative — bounding each independently — was
written first and rejected on inspection: it produced `clean=173 raw=169` for one
`--max-output=120` reply, two different windows with one omitted count.

The mutual-exclusion check goes in `extract_options`, so it covers every
subcommand at once rather than `send` alone.

Bounding stays in the command, not the supervisor: the transcript, the cursor and
every attached client must still see the whole stream.
