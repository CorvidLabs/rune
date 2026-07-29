---
change: CHG-0012-restore-full-cli-contract-detail-after-the-help-delta-and-establish-exact-semant
artifact: context
---

# Context

CHG-0010 correctly added the help contract but its semantic delta compressed previously accepted
stdout-purity rationale and several concrete behavioral examples. It also used a broad `specs`
affected-path prefix, which did not satisfy the exact `specs/cli/cli.spec.md` successor coverage
required by CHG-0008.

This documentation change restores the full rationale, retains the accepted help guarantees, and
declares the exact canonical path through a real semantic delta.
