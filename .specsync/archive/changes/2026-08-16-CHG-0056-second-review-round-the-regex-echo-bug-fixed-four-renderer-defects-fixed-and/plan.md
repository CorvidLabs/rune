---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: plan
---

# Plan

1. Verify each reported finding independently before acting, since the refutation pass had already
   corrected four severities.
2. Take the echo machinery, measure it on the settle path as well as the regex path, and report
   both results rather than the flattering one.
3. Fix the four renderer defects, each against an established oracle.
4. Document what remains, including the rule that was tried and disproved.
