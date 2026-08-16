---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: tasks
---

# Tasks

- [x] `scripts/check_provenance.rb`, wired into the release lane
- [x] fails when attest is absent, when no previous tag exists, and when any commit lacks a record
- [x] every failure names the remedy
- [x] docs reordered so signing precedes the lane; the test that pinned the old order updated
- [x] README and CHANGELOG
