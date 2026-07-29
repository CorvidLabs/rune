---
change: CHG-0003-bind-the-existing-plugin-version-input-to-strict-specsync-release-ownership
artifact: context
---

# Context

The release branch changed `plugin.toml` to version 0.2.1 before strict SDD policy treated that package input as meaningful. CHG-0002 correctly strengthened the policy, which then exposed that the existing plugin version bump had no declared change owner. The CLI v3 contract already requires plugin and gem version parity, so no further canonical spec change is needed.
