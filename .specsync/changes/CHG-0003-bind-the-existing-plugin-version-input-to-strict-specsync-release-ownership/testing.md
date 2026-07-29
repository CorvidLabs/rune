---
change: CHG-0003-bind-the-existing-plugin-version-input-to-strict-specsync-release-ownership
artifact: testing
---

# Testing

- `fledge run version-check` proves `plugin.toml` matches `Rune::VERSION`.
- `fledge run spec-check` proves the changed plugin input has an active approved owner.
- `fledge lanes run release` verifies the complete package.
- `fledge trust verify --range main..HEAD` confirms lifecycle, contract, risk, and provenance gates.
