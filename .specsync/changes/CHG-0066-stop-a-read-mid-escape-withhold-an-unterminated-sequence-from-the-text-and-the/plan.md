---
change: CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the
artifact: plan
---

# Plan

`OutputLimiter` already owned the machinery — `DANGLING_ESCAPE`, `dangling_at`
and `window_before`, used to resync at a `--max-output` cut. It was simply never
applied at a read boundary. `dangling_suffix` exposes it, and `read_result`
withholds the suffix from the sliced text and subtracts its length from the
reported cursor.

`list` needed a different fix for the same root cause: it summarised the last
*event* on its own, and a pty read boundary is neither a line boundary nor a
sequence boundary. It now joins the output events in the tail before stripping.

A child that opens a sequence and never closes it withholds those bytes
indefinitely. That is deliberate and matches a terminal, which displays nothing
for them either.
