---
change: CHG-0044-bound-a-session-transcript-on-disk-as-well-as-in-memory-rotating-it-while-keepi
artifact: testing
---

# Testing

Four tests: the file stays under the ceiling after 42MB of output; dropped plus retained equals
written exactly; a cursor from after the rotation resolves to the exact byte count; and a cursor from
before it returns what is still held. All four fail against the unbounded version.

They drive the log path directly rather than through a live session, because producing 40MB through
a real child takes eighty seconds and the property under test is arithmetic, not timing.

370 examples, 0 failures; lint clean.
