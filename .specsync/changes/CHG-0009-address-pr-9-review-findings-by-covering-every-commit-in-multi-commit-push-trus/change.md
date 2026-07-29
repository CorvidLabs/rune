---
id: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
state: verifying
type: bug_fix
base_commit: 605e5d42445c9cc4ff61a5ec9ef958e16245a09c
---

# Address PR #9 review findings by covering every commit in multi-commit push trust ranges and keeping non-PTY E2E tests loadable without Ruby's optional pty extension

## Intent

Address PR #9 review findings by covering every commit in multi-commit push trust ranges and keeping non-PTY E2E tests loadable without Ruby's optional pty extension

## Affected Canonical Specs

- None

## Acceptance Criteria

- 1. Push-triggered CI derives the Augur and Attest range from GitHub's exact before and after SHAs, and a three-commit push produces a range containing all three commits. 2. Partial, all-zero initial-push, missing-commit, unsupported-event, and empty ranges fail closed instead of falling back or passing vacuously. 3. Pull-request CI continues to use origin/main..HEAD and local fledge trust retains its non-empty main-branch fallback. 4. spec/rune/e2e_spec.rb loads when Ruby's optional pty extension is unavailable; non-PTY version and command-inventory examples run while only PTY-backed examples skip. 5. Automated regression tests exercise a real temporary Git history and a subprocess with a simulated missing pty extension. 6. Fledge verify, smoke, strict SpecSync, Augur, and Attest gates pass.

## No-spec Rationale

This corrects CI range selection and test-suite portability without changing Rune's public API or canonical runtime behavior; CHG-0008 already owns the stdout-purity and non-vacuous trust guarantees.
