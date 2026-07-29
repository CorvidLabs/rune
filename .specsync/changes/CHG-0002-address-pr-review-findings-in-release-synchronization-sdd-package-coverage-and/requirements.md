---
change: CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and
artifact: requirements
---

# Requirements

- REQ-001: The version setter MUST repair a stale source when another source already equals the requested version.
- REQ-002: The version setter MUST validate every source pattern before writing any file.
- REQ-003: SpecSync MUST treat `bin/`, `spec/`, `Gemfile`, `Gemfile.lock`, `plugin.toml`, and `rune.gemspec` as meaningful delivery inputs.
- REQ-004: Package publication MUST require an exact Git tag with the requested release name.
- REQ-005: Package publication MUST require the release tag commit to be reachable from `origin/main`.
- REQ-006: Release provenance and version-parity checks MUST remain mandatory.
