---
change: CHG-0053-fail-the-release-before-the-tag-when-provenance-is-missing-not-after-it
artifact: design
---

# Design

`provenance-check` runs `attest verify` over `<previous release tag>..HEAD` and is the release
lane's second step, beside `version-check` — both are cheap and both answer whether this should be
a release at all.

Two details carry most of the value:

**It refuses to pass when it did not run.** A gate that goes quiet because its tool is missing
reports success for a check it never performed, which is the failure being fixed, one level up. An
absent command raises `ENOENT` out of `Open3`, so that is caught and turned into a loud failure
rather than a backtrace.

**The range excludes a tag pointing at HEAD.** Otherwise re-running the gate on an already-tagged
release inspects nothing and passes — the same vacuous-pass that `scripts/trust_range.sh` existed
to prevent before it was removed.

CI is untouched. Re-adding CI-side attestation would walk back `a15e73f` before spec-sync 6 has
landed, and the failure was never the mechanism.
