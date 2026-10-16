---
change: add-isolated-rune-session-fault-and-recovery-verification
artifact: testing
---

# Testing

## Observed macOS evidence

- All 17 new examples passed, receipt `20261016T045637Z-R1-f73450`.
- Three identity-refusal probes passed, `20261016T045613Z-R1-fcd317`.
- Complete RSpec suite: 659 examples, zero failures,
  `20261016T045947Z-R1-72ffba`.
- All seven coherent disposable-product mutants completed setup and were
  rejected by the expected assertions, `20261016T045919Z-R1-42d607`.
- Injected old-cleanup control was rejected: no raised failure, fixture lost,
  missing cleanup-refusal evidence, `20261016T045902Z-R1-0e12c9`.
- Spec lint passed (one file; harness remains excluded by existing config),
  `20261016T050250Z-R1-344aca`.
- Version, strict spec (32/32 files, 100%) and canonical lifecycle checks passed,
  receipts `050300-f01d69`, `050311-5dde38`, `050333-9d30dc` on 20261016/R1.
- Native Trust passed and reran all 659 examples,
  `20261016T050350Z-R1-0a9275`. This precommit range was empty; committed-range
  risk verification is still required before publication.

The zero-example filter at `045121-d1a3f8` and negative-control setup error at
`045822-79cc71` are explicitly not passing evidence. All receipts and complete
logs are retained outside the source tree in the coordinator report directory.
This records engineering observations, not human acceptance or hosted Ruby
matrix qualification. No production fix or cross-platform pass is claimed.
