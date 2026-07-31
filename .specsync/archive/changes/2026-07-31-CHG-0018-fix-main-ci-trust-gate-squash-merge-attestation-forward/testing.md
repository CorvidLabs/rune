---
change: CHG-0018-fix-main-ci-trust-gate-squash-merge-attestation-forward
artifact: testing
---

# Testing

- Unit: `spec/squash_attest_forwards_spec.rb` covers usage errors, missing SHAs,
  empty (no-PR) ranges, and multi-commit TSV emission via a stubbed `gh`.
- Local: map real main push ranges for PRs #23/#24/#26; fetch `refs/pull/N/head`;
  `attest forward` each pair; `attest verify` of the full range passes.
- CI: PR Trust gate green; post-merge push to main must pass Attest after this
  lands (the failure mode under test).
