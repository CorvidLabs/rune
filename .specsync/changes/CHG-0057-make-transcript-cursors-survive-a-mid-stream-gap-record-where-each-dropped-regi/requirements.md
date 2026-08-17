---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: requirements
---

# Requirements

1. A cursor issued before a mid-stream gap resolves to the output that followed it. It never returns
   bytes the caller has already been given.
2. A cursor landing *inside* a gap clamps **forward** to the gap's end. Those bytes are gone either
   way; returning later output is honest, returning earlier output is not.
3. `cursor` still equals the total bytes the child produced, including everything dropped.
4. The single-prefix case — every rotation — collapses to exactly today's arithmetic, byte for byte.
5. Output that no transcript write could record is carried and emitted as a `truncated` event by the
   next write that succeeds, so `read` can resolve a cursor issued during the outage.
6. While a gap is still owed, the supervisor reports `transcript_gap_bytes` — the only place the
   skew is known, because nothing on disk records it yet.
7. A rotation's accounting counts exactly what the reader reconstructs from the kept region: its
   output, plus any `truncated` it already records, and never a fragment the reader cannot parse.
