---
change: CHG-0005-restrict-release-version-matching-to-the-plugin-toml-table
artifact: testing
---

# Testing

- A malformed `[plugin]` table followed by another table with `version` is rejected by the checker.
- The setter rejects the same fixture without modifying either version source.
- A valid `[plugin]` version still passes parity checks and synchronized updates.
- `fledge lanes run release`, strict SpecSync, trust, provenance, and GitHub CI remain green.
