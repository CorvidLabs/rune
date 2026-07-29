---
change: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
artifact: tasks
---

# Tasks

- [x] T1 `.github/workflows/ci.yml`: use exact push before/after boundaries and reject unsupported
      event types.
- [x] T2 `scripts/trust_range.sh`: validate paired push boundaries, commit availability, the
      all-zero sentinel, and non-empty ranges.
- [x] T3 `spec/trust_range_spec.rb`: exercise a real three-commit push and fail-closed cases.
- [x] T4 `spec/rune/e2e_spec.rb`: remove the unconditional PTY require and skip the run example
      when the extension is unavailable.
- [x] T5 `spec/rune/e2e_portability_spec.rb`: execute the E2E file with a simulated missing PTY
      extension.
- [x] T6 `CHANGELOG.md`: document the trust-range and test-portability corrections.
- [x] T7 Refresh CHG-0008 evidence and prepare CHG-0009 for strict verification and acceptance.
- [x] T8 Exercise the complete Fledge verification and smoke gates before recording closing evidence;
      Augur and Attest run again on the final staged commit.
