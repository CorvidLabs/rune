---
change: CHG-0004-restrict-release-provenance-ranges-to-semantic-release-tags
artifact: research
---

# Research

`git describe --tags` considers every tag, including lightweight internal tags. `git describe --match <pattern>` filters candidates before selecting the nearest reachable tag. Rune release versions and tags use strict numeric `vMAJOR.MINOR.PATCH` values.
