---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: docs
---

# Docs

`docs/releasing.md` loses the signing steps and renumbers, and its opening now states why
provenance is not gated rather than describing a gate that no longer runs. README drops the attest
bullet. The CHANGELOG entry sits under the unreleased 0.8.0 section, since that release is not yet
tagged.
