---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: context
---

# Context

`supervisor.rb` had reached 980 lines and `session_command.rb` 846, which is more than either
can carry legibly. More to the point, four rounds of review have now found defects in one part of
that file — the decision of when a send has been answered — and each fix had to be reasoned about
through an event loop that also owns a pty, a control socket, a write queue and a teardown path.

Every one of those bugs was a rule about *this send* being evaluated against the wrong facts: the
echo compared in bytes rather than characters, a regex matched against text that included the echo,
a settle fired before the input had been submitted. None of them needed a pty to demonstrate, and
none of them could be demonstrated without one.
