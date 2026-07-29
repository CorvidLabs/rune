---
change: CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and
artifact: design
---

# Design

1. Validate that every version pattern exists before writing either version file. A file already containing the target version is valid and remains unchanged.
2. Add Ruby package, dependency, executable, and test inputs to `meaningful_paths`.
3. Before provenance verification, fetch `origin/main`, require an exact `refs/tags/$RELEASE_TAG`, and require the peeled tag commit to be an ancestor of `origin/main`.
4. Apply the same release-ref validation to both GitHub Packages and RubyGems.org jobs.
5. Keep the existing provenance and version-parity checks after the ref validation.
