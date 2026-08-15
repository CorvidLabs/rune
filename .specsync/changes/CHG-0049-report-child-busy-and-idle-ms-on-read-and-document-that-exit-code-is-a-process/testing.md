---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: testing
---

# Testing

One test drives a child that prints for a couple of seconds and then stops, asserting `child_busy`
is true during and false after. It polls for the observable transition rather than sleeping a guessed
interval, except for one deliberate pause past the settle window, which is the property under test.

387 examples, 0 failures; lint clean.
