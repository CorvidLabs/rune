---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: context
---

# Context

The releases for v0.4.0, v0.5.0 and v0.6.0 all failed to publish, at the same step, in about fifteen
seconds each. `.attest.json` requires an attestation reporting passing tests, and the documented
step in `docs/releasing.md` that records one was skipped three times running.

Nothing downstream broke, which is exactly why nobody looked: the Homebrew formula builds from the
tag tarball and the rubygems.org job is disabled, so the only casualty was a GitHub Packages gem
nobody installs.

The mechanism was never missing. `a15e73f` removed the Augur and Attest gates from CI
deliberately — recorded as an interim position pending spec-sync 6 — and moved provenance to a
manual step. The defect is that the check ran *after* the tag existed and the release was announced,
where its failure could be ignored indefinitely.
