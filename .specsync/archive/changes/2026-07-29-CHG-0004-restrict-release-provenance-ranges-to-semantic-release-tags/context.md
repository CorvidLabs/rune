---
change: CHG-0004-restrict-release-provenance-ranges-to-semantic-release-tags
artifact: context
---

# Context

Both publish jobs resolve the provenance base with unrestricted `git describe --tags`. An unrelated checkpoint tag between semantic releases can therefore shorten the Attest range and omit commits that should be verified. The latest PR review identified this after the previous fixes were pushed.
