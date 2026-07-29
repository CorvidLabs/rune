---
change: CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery
artifact: docs
---

# Docs

Update the release guide to state that release-prep changes must use the SpecSync change lifecycle
and that source/spec staleness, lifecycle status, and verified-change coverage are blocking gates.
Keep the exact local and CI commands in `fledge.toml` and `.github/workflows/ci.yml` as executable
truth; avoid duplicating implementation-sensitive flags elsewhere unless needed for release
operators.
