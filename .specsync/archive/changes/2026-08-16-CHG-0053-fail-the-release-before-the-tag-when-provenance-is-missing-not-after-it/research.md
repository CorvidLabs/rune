---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: research
---

# Research

| release | publish result | step |
|---|---|---|
| v0.4.0 | failure, 12s | Verify Release Provenance |
| v0.5.0 | failure, 15s | Verify Release Provenance |
| v0.6.0 | failure, 15s | Verify Release Provenance |

Reproduced locally: `attest verify --range v0.6.0..HEAD --policy .attest.json` reports
`requireAttestation` and `requireTestsPassed` violations on every commit in the range.

The distribution path does not run through the gem at all — `homebrew-tap/Formula/rune.rb` sets
`url` to `archive/refs/tags/vX.Y.Z.tar.gz` and builds from source, and the rubygems.org job is
`if: false`. That is why three failures produced no visible symptom.
