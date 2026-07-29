---
change: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
artifact: context
---

# Context

PR #9 fixed Rune's agent-mode watch stream and prevented empty trust ranges, but its automated
review identified two valid follow-up defects before the accepted change could be archived.

First, push CI used `HEAD~1..HEAD`. A two-or-more-commit push made that range non-empty while
excluding every pushed commit except the tip, so the guard passed and both Augur and Attest ignored
earlier commits. GitHub's push payload provides the exact `before` and `after` SHAs needed to cover
the entire batch.

Second, `spec/rune/e2e_spec.rb` required Ruby's optional `pty` extension at file load. Rune's
runtime intentionally rescues a missing extension so non-PTY commands remain usable, but the test
file crashed before it could skip PTY-backed examples. This particularly affects Windows and
minimal Ruby installations.

CHG-0008 is reopened only to refresh its immutable accepted delivery evidence for the exact files
being corrected. This change records the new review-specific outcomes and depends on CHG-0008.
