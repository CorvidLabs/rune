---
id: CHG-0026-touch-cli-spec-md-change-log-to-close-the-stale-gate-for-the-0-3-0-version-bum
state: accepted
type: documentation
base_commit: 4b657c0956081708b3172e1710aafe96dcc396b3
---

# Touch cli.spec.md Change Log to close the --stale gate for the 0.3.0 version bump

## Intent

Touch cli.spec.md Change Log to close the --stale gate for the 0.3.0 version bump

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- specs/cli/cli.spec.md's Change Log records CHG-0025's version bump; specsync check --stale 1 no longer flags cli as behind lib/rune/version.rb; fledge run spec-check passes with 0 warnings under --strict.

## No-spec Rationale

Change Log audit entry only, recording the version bump already delivered in CHG-0025; no Public API, Invariants, or contract content changed.
