---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: plan
---

# Plan

1. Re-apply the gap-recording half of the durability prototype by hand: `@log_gap`, `TORN_MARKER`,
   `append_log`/`write_record`/`gap_line`/`note_log_gap`/`writable_log`, `gap_field` on `status` and
   on the settle reply, and the rotation backoff the reopening handle makes necessary.
2. Fix `Store#output_bytes_from` so it counts exactly what `Transcript.load` parses.
3. Make `Transcript` gap-aware: record each gap at load, map cursors through the list, clamp forward.
4. Build a harness that measures the mapping against an independent oracle, and the rotation
   accounting against the bytes the child produced.
5. Prove each fix with a test that fails when that fix alone is reverted.
