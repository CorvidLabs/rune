---
change: CHG-0004-restrict-release-provenance-ranges-to-semantic-release-tags
artifact: testing
---

# Testing

- RSpec asserts both publish jobs use `git describe --match "$release_tag_pattern"`.
- A temporary Git history proves an intervening non-release tag is ignored in favor of the prior semantic release tag.
- `fledge lanes run release` verifies the full package.
- Strict SpecSync verifies CHG-0001, CHG-0002, and CHG-0004 against the final workflow.
- `fledge trust verify --range main..HEAD` and GitHub CI remain green.
