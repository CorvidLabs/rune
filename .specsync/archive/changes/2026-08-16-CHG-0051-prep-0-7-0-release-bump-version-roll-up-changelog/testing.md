---
change: CHG-0051-prep-0-7-0-release-bump-version-roll-up-changelog
artifact: testing
---

# Testing

`fledge lanes run release`: version-check, fmt-check, lint, the full suite, spec-check,
spec-lifecycle, the smoke tests against a real pty, and the gem build.

`version-check` is the one that matters here — it is the gate that catches three version strings
drifting apart, which is the failure mode a hand-edited release prep actually has.
