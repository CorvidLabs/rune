---
change: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
artifact: testing
---

# Testing

411 examples, up from 384. Every new test was confirmed to fail against the unfixed code.

Two testing notes worth keeping. A scroll-region expectation was hand-derived and wrong; it now
carries the value the reference emulator produces, with a comment saying so. And a flag-parsing test
first failed because it called a method that does not exist — the test was wrong, not the code, and
finding that out took running it.

The reviews' own harnesses were wrong several times before they were right, which is why every
finding here was reproduced independently before being acted on.
