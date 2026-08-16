---
change: CHG-0055-turn-the-provenance-gate-off-and-record-why-instead-of-leaving-it-to-fail
artifact: tasks
---

# Tasks

- [x] `.trust.toml` records the off state and the reason
- [x] `provenance-check` and `scripts/check_provenance.rb` removed
- [x] attest steps and their range resolution removed from both publish jobs
- [x] tag and version validation confirmed still present in both jobs
- [x] tests retargeted; guide, README and CHANGELOG updated
