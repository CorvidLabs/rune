---
change: CHG-0017-cover-ndjson-error-dispatch-at-the-cli-integration-boundary
artifact: testing
---

# Testing

Invoke `Rune::CLI` with `nonexistent --ndjson`, parse the complete captured stdout as JSON, and assert the stable error event, status, and message. This is test-only coverage of the canonical CLI invariant changed by CHG-0016.

Evidence: the CLI/renderer integration set passes 35 examples with 0 failures, and strict SpecSync reports 4 specs with 0 errors and 0 warnings.
