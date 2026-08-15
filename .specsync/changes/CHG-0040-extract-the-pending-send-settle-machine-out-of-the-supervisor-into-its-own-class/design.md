---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: design
---

# Design

`Session::PendingSend` holds one in-flight send and answers one question: given the transcript
slice and the facts the loop knows, is this send finished? It touches no IO at all. The supervisor
passes `now`, `child_finished`, `submitted` and `last_output_at` rather than reaching for
ivars, which is what makes each rule testable in isolation.

Moved with it: echo location and the partial-echo grace window, the bounded regex match, the quiet
window, the deadline, and the rule that nothing settles a send whose input has not been submitted.
Left behind: everything that needs the loop — the transcript, the write queue, the clock itself.

`Supervisor` keeps `child_still_talking?`, because `busy_at_send` is a fact about the child at
the moment of the send rather than about the send.
