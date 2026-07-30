---
change: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
artifact: plan
---

# Plan

1. Resolve push trust ranges from the event's exact before/after SHAs and fail closed on unsupported
   or malformed boundaries.
2. Add real temporary-repository tests covering a three-commit push plus partial, all-zero, and
   empty boundaries.
3. Remove the E2E file's unconditional PTY load, skip the PTY-backed run example when necessary,
   and simulate a missing extension in a subprocess regression test.
4. Refresh CHG-0008's unchanged accepted delivery evidence, then verify and accept CHG-0009's
   review-specific no-spec-change contract.
5. Run the complete Fledge verification, smoke, SpecSync, Augur, and Attest gates and publish one
   follow-up pull request.
