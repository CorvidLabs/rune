---
change: CHG-0061-release-0-9-0-bump-the-version-and-record-the-round-s-measurements
artifact: plan
---

# Plan

Bump the version strings, date the changelog heading, add the two fixes made this
round and a "Verified, not changed" section for the two durability claims that
were observed rather than altered.

Rewrite the roadmap table with each entry re-run. The oversized-send entry is
corrected in place with the measurement that contradicts it rather than deleted,
because the correction is the useful part: it claimed sends were silently
discarded, and they are neither silent nor discarded.

`Gemfile.lock` is in scope because its `PATH` stanza records the gem's own
version and bundler rewrites it on the first local run after a bump. The
`BUNDLED WITH` stanza bundler also wanted to add is left out: this repository has
never carried one, and pinning a bundler version in a release commit is a way to
fail a CI runner that has a different one.
