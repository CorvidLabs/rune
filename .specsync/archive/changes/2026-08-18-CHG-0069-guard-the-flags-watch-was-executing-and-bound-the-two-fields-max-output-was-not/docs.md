---
change: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
artifact: docs
---

# Docs

`watch.spec.md` invariant 20 carries the guard, the measurement, and the
leading-position limitation. `pty_runner.spec.md` invariant 29 carries the stream
bound. `session.spec.md` 41p carries `--grep` honouring `--since`, including that
context windows are taken within the slice.

Export rows follow the code: `flag_error` and the two templates are now `cli`
exports, `scan_head`/`leftover_flag_error`/`VALUE_FLAGS` are `watch` exports, and
the two rows for what moved out of `RunCommand` are gone from `pty_runner`.

Worth naming as an API change: `RunCommand::INLINE_VALUE_ERROR` still resolves
through inheritance but now carries a second placeholder, so
`format(..., name:)` alone raises `KeyError`. It was introduced days ago and has
never appeared in a tagged release, so the exposure is a caller who took it from
main.

A specsync extractor quirk worth recording: `apply_output_limit` and
`execute_pty` are surfaced as exports and must be documented, while
`bound_stream` — a private instance method beside them, at the same level in the
same class — is not surfaced at all, and documenting it is a hard error
("Spec documents 'bound_stream' but no matching export found in source"). So the
spec documents its two neighbours and not it. That asymmetry is not something
this change can fix, and guessing at it would just move the error around.
