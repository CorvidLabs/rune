---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: design
---

# Design

`write_to_child` enqueues the text and schedules the terminator for `SUBMIT_DELAY` (50ms) later
instead of appending it. `deliver_submit`, called once per event-loop tick, writes the terminator
only once the delay has passed *and* the text has fully drained from the outbox — both conditions
are needed, since a queued write would otherwise be coalesced into the same read.

`flush_submit` writes an outstanding terminator immediately and is called at the top of
`write_to_child`, so two sends in quick succession produce text, CR, text, CR rather than losing
one.

The delay is a constant rather than a flag. It is invisible next to a model round trip, and a flag
would ask callers to know something about the callee's input handling that they cannot reasonably
determine.
