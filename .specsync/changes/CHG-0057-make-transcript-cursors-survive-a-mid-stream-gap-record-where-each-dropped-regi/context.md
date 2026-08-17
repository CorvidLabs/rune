---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: context
---

# Context

`Transcript#from(since)` computed `since - dropped` against a single global accumulator. That is
correct only while the dropped region is a **prefix** of the stream — true for log rotation, which
until now was the only thing that emitted a `truncated` event.

The durability work emits `truncated` **mid-stream**, when a transcript write fails and the bytes
the child produced cannot be recorded. Nothing adjusted `from`. Reproduced against the real class
with 25 chunks x 4000B, a 48_000-byte mid-stream gap and 25 more (cursor 248_000, dropped 48_000,
retained 200_000):

| `since` | bytes returned | first bytes | |
|---|---|---|---|
| 100_000 | 148_000 | `aaaa` | 48_000 bytes of already-delivered output, replayed |
| 148_000 | 100_000 | `bbbb` | correct by accident — the cursor is the gap's end |
| 228_000 | 20_000 | `bbbb` | correct |

Every cursor issued *before* a gap resolved |gap| bytes too early. For an agent polling
`read --since=<last cursor>` — the primary loop — that is re-delivered output presented as new,
which re-fires prompt detection and every "did my command finish" check built on it.

Two accounting bugs sat underneath it. A rotation's head event is `total_output - kept`, so anything
the kept region accounts for and the scanner does not is counted twice, and anything the scanner
counts that the reader will not is a permanent shortfall. `output_bytes_from` did both: it ignored a
`truncated` event inside the kept tail, and it counted a torn fragment that `Transcript.load` parses
and skips.
