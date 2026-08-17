---
change: CHG-0063-assert-the-geometry-rune-guarantees-not-the-scheduler-that-usually-delivers-it
artifact: testing
---

# Testing

Both specs pass locally (2 examples, 0 failures) and the full suite is green at
539 examples. The real verification is CI, since the failure only ever appeared
on a Ruby 3.1 runner — that is the point of the change, and the reason it is not
being called fixed on the strength of a local run.
