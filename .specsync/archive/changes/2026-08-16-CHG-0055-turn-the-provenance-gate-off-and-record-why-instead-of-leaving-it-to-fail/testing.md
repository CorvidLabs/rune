---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: testing
---

# Testing

405 examples, down from 411 because `spec/provenance_check_spec.rb` went with the script it tested.

The two tests that asserted on the removed workflow steps were **retargeted rather than deleted**,
which is the part worth keeping. One now asserts the workflow does *not* reference attest and that
`.trust.toml` declares the off state — so the state stays declared. The other pins the release
guide's shape: no signing step, and the lane before the tag. That guide has drifted twice already,
once describing a CI gate that had been removed and once an ordering the lane would have failed on.
