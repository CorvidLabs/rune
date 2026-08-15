---
change: CHG-0036-restore-the-send-settle-default-to-800ms-and-correct-the-0-4-0-measurement-whic
artifact: testing
---

# Testing

No test asserts the default value; every settle-dependent spec passes `--settle-ms` explicitly,
which is why this is a one-line change. 340 examples, 0 failures; lint clean.

The evidence for the default itself is the re-measurement, which is recorded in research.md rather
than encoded as a test: it needs live agent CLIs and several minutes per window, so it belongs in
dogfooding rather than in CI.
