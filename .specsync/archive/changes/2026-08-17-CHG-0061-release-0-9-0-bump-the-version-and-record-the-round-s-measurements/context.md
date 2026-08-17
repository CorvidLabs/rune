---
change: CHG-0061-release-0-9-0-bump-the-version-and-record-the-round-s-measurements
artifact: context
---

# Context

0.9.0 closes the round that began with a field report from driving `grok` and
`kimi` through real spec-sync work, plus a session of dogfooding against the same
children.

The release itself is the version bump and the record. What it records is worth
more than the bump: `ROADMAP.md` listed eight findings as "known, unfixed, and
queued for 0.9.0", and re-running each against the tree found seven already
closed and one wrong about its own mechanism. A table of defects nobody re-runs
becomes fiction at about the rate the code improves.
