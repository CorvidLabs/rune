---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: testing
---

# Testing

The sliced-sequence test loops over every cut offset within the leading sequence rather than picking
one, because which offset a real cut lands on is arbitrary.

Both sides of the bound are tested, and this is the part worth keeping: a stream with no escapes at
all must keep its text, and an escape further away than the scan must not pull the cut to it. The
fix is only correct if it does nothing in those cases.

Confirmed the tests fail against the unfixed renderer — 1 failure — and pass with it. 378 examples,
lint clean.
