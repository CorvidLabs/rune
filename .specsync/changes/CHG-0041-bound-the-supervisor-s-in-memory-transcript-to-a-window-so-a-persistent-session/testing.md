---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: testing
---

# Testing

Three tests: the held window stays bounded while the cursor keeps counting everything; an in-flight
send still gets its whole slice past the backlog bound; and an attaching terminal still receives
exactly the backlog. The first two fail against the unbounded version.

They are white-box because the property is about what the process holds, which is not observable
from outside it. The end-to-end evidence is the measurement in research.md, which needs a running
session and two and a half minutes — dogfooding rather than CI.

363 examples, 0 failures; lint clean.
