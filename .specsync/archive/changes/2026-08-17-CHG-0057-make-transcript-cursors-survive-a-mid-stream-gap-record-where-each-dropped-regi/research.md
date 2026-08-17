---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: research
---

# Research

Measured with `harnesses/transcript_gaps.rb`, which lays a stream out byte by byte, so the expected
answer comes from the layout rather than from the code under test, and evaluates the shipped
arithmetic and the new mapping against the same loaded transcript.

Cursor mapping, bytes returned (oracle / before / after):

| case | probe | oracle | before | after |
|---|---|---|---|---|
| no gap | every boundary | — | exact | exact (byte-identical) |
| rotation only (prefix) | every boundary | — | exact | exact (byte-identical) |
| one mid-stream gap | since=100_000 | 100_000 | 148_000 (48_000 replayed) | 100_000 |
| one mid-stream gap | since=124_000 (inside) | 100_000 | 124_000 (24_000 replayed) | 100_000 |
| several gaps | 19 probes before/inside/after each | — | up to 60_000 replayed | exact at every probe |
| rotation over a gap | 12 probes | — | up to 12_000 replayed | exact at every probe |

Rotation accounting, cursor skew against the bytes the child produced (0 is correct):

| transcript | before | after |
|---|---|---|
| healthy, no torn write | 0 | 0 |
| 400_000-byte gap inside the kept tail | +400_000 | 0 |
| 1 / 4 / 10 torn writes in the kept tail | -4096 / -16384 / -40960 | 0 |
| torn write plus the gap it opened | +16384 | 0 |

The torn-write row is worse than 0.8.0's flat -4096 because `TORN_MARKER` terminates each fragment
into a countable line of its own, so the error scales with the length of the outage.

Agreement between `Store#whole_record?` and what `Transcript.load` parses, swept over every split
point of every record shape with braces, quotes, escapes and the marker's own bytes in the payload:
0 disagreements in 1760 cases, 10 with the last-line parse branch removed.
