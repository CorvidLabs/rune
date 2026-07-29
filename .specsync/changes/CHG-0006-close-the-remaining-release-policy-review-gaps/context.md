---
change: CHG-0006-close-the-remaining-release-policy-review-gaps
artifact: context
---

# Context

The latest PR review found three remaining release-policy gaps. The broad `.specsync/` ignore prefix
can exempt meaningful policy files, publish jobs accept unprefixed semantic-version tags, and the
post-merge runbook verifies trust before the merge commit has an Attest record.
