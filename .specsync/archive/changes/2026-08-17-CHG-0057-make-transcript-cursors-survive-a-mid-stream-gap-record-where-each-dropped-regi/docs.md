---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: docs
---

# Docs

`docs/sessions.md`: `dropped_bytes` now covers output lost to a failed write as well as to
rotation, a cursor that lands inside a dropped region resolves to the output that followed it, and
`transcript_gap_bytes` appears on `status` and on a `send` reply while a hole is still owed.

`specs/session/session.spec.md`: Public API entries for the new exports, and invariants 41w (a
failed write is recorded), 41x (`TORN_MARKER`), 41y (a cursor is mapped through each dropped region)
and 41z (a rotation counts what the reader reconstructs).
