---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: design
---

# Design

**`Transcript.load` records where, not just how much.** Each `truncated` event becomes a gap of
`(retained offset, cumulative dropped)`. Two recorded at the same offset — a rotation's head event
over a tail that already began with one — are one hole and are merged, which keeps the prefix-only
case a single entry.

**`retained_offset` walks the list.** For each gap in order: a cursor before it maps by the total
dropped *so far*; a cursor inside it returns the gap's retained offset (clamp forward); otherwise
carry the cumulative total and continue. With one gap at the head this reduces to `since - dropped`
exactly, which is what keeps every rotation test untouched.

**The supervisor carries what it could not write.** `log_event` no longer swallows a failed write:
the output bytes go into `@log_gap`, and the next successful write emits them as a `truncated`
record first. Each record is written on its own, and the first record after a failure is preceded by
`TORN_MARKER`, so any fragment the failed write left cannot parse — which is what lets "recorded"
mean exactly "its own write returned". `writable_log` reopens a handle that has gone away, and
`rotate_log` backs off for `ROTATE_RETRY_SECONDS` after a failure rather than re-scanning the tail
it means to keep on every subsequent event.

**`output_bytes_from` counts what the reader parses.** A `truncated` in the kept region counts as
the bytes it names; a line is counted only if it is a whole record, decided on its last byte because
parsing the kept region cost 96MB per rotation. A line with no trailing newline is the file's last
and is parsed outright — the one shape a byte test cannot decide.

**Deliberately not taken from the durability prototype**: the orphan guard (`Store.group_alive?` and
the `archive`/`start` refusals), which another stream owns, and `rotate_output`'s close-ordering
restructure, which belongs to "a rotation that fails costs only the rotation" rather than to gap
recording.
