---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: testing
---

# Testing

The first test is the one that matters: with an empty `PATH`, the check must **fail**, not pass.
It caught a real bug on its first run — `capture` raised `ENOENT` instead of returning nil, so
the missing-tool path I had written a comment about did not work.

An existing test in `release_version_check_spec.rb` pinned the old documentation order and now
fails correctly, because the order genuinely changed: verification moved into the lane, and signing
has to precede it. Updated rather than deleted — the ordering is still worth pinning, just a
different ordering.

384 examples, lint clean.
