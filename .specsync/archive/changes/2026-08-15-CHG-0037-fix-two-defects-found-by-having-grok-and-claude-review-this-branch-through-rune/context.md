---
change: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
artifact: context
---

# Context

Dogfooding before the release, by using rune to do the actual work: driving grok, claude and agy
through `rune session` to review this branch. Every prompt was 790 characters, well past the ~64
that used to fail to submit, so the exercise doubled as validation of that fix.

Both reviewers found a real defect that the three earlier rounds of review and the whole test suite
had missed. Neither is in old code — both are in the hardening work added on this branch.
