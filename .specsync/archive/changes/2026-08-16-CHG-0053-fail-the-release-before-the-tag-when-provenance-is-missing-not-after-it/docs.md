---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: docs
---

# Docs

`docs/releasing.md` states why the publish workflow's copy of this check is too late to be useful,
and reorders the post-merge steps so signing precedes the lane. The prep section now spells out that
every commit needs a record, not only the merge commit — the omission that caused this.

README notes attest is gated by the release lane. CHANGELOG records both this and the screen-tail
fix under Unreleased.
