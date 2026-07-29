---
change: CHG-0006-close-the-remaining-release-policy-review-gaps
artifact: design
---

# Design

Ignore only generated SpecSync change and cache state while leaving policy files meaningful. Add the
same anchored `vMAJOR.MINOR.PATCH` validation to both publish jobs before any tag resolution. Reorder
the runbook so release verification precedes signing, and signed provenance precedes trust checks.
