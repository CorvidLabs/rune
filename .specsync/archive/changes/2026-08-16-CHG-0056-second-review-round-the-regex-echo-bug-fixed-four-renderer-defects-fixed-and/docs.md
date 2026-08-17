---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: docs
---

# Docs

`docs/sessions.md` replaces the `--wait-for-regex` limitation with what it now does and an honest
bound on the claim — every echo shape that could be captured is excluded, not *cannot happen* — and
gains a prominent limitation on the settle path, with the measurements and a workaround.

`ROADMAP.md` records the disproved rule and both counterexamples, so the next attempt starts past
the dead end rather than in it. The CHANGELOG corrects 0.8.0's settle claim, which was true for the
case measured and read as more general than it is.
