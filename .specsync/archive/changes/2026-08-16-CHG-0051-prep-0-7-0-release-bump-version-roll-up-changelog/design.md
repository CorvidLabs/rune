---
change: CHG-0051-prep-0-7-0-release-bump-version-roll-up-changelog
artifact: design
---

# Design

`fledge run set-version -- 0.7.0` updates the version constant and the plugin manifest;
`bundle install` refreshes the lockfile.

The lockfile diff is held to the version line alone. `bundle install` also wanted to add a
`BUNDLED WITH 4.0.16` stanza that was not there before, which would pin every contributor and CI
job to one bundler — a change to how the project builds, smuggled in under a version bump. Removed.

The notes carry a **Not fixed, deliberately** section. A release that quietly omitted the screen
tear would read as though the report had been fully addressed.
