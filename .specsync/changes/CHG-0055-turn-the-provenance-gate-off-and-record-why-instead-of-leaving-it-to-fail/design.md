---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: design
---

# Design

Turned off *through* the trust toolchain rather than around it. `.trust.toml` supports
`provenance.mode = "off"` and refuses it without a `skip_reason`, which is the right shape:
the tooling insists you say why. The reason is recorded there in full.

`provenance-check` and its script are removed, since they exist only to enforce this. The attest
steps come out of both publish jobs, along with the release-range resolution that fed them and
nothing else.

What stays: `Verify Release Tag Is on Main` and `Verify Release Version` in both jobs, and
`version-check` in the lane. Those are the checks that stop a wrong release; provenance never was.
