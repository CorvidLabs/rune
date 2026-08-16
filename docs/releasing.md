# Releasing rune

Releases are prepared in a pull request and published only from a tag on `main`. The package
workflow refuses to publish when the tag differs from the gem/plugin version, or when the tag is not
an exact `vMAJOR.MINOR.PATCH` reachable from `origin/main`.

**Provenance is no longer gated.** It required signing every commit by hand before a release, and
that step was skipped for v0.4.0, v0.5.0 and v0.6.0 without anyone noticing — because the only thing
gated on it was a GitHub Packages gem that nothing installs. The Homebrew formula builds from the
tag tarball and the rubygems.org job is disabled. Enforcing it in the release lane instead just
blocked releases on a human keystroke. `.trust.toml` records `provenance.mode = "off"` with the
reason, rather than leaving a gate to keep failing.

## Prepare the release pull request

1. Start from an up-to-date `main` branch.
2. Update both version sources through Fledge:

   ```sh
   fledge run set-version -- MAJOR.MINOR.PATCH
   ```

3. Curate `CHANGELOG.md` and update the release record in `ROADMAP.md`.
4. Run the complete release gate:

   ```sh
   fledge lanes run release
   ```

5. Commit, push, and open a pull request. Do not create the release tag from the prep
   branch.

## Tag and publish after merge

Once the release-prep pull request is merged:

1. Update local `main` and run the release lane against the merge commit:

   ```sh
   git switch main
   git pull --ff-only
   fledge lanes run release
   ```

2. Wait for the `main` CI run to pass.

3. Create and push the tag without changing the already-reviewed version or changelog:

   ```sh
   fledge release MAJOR.MINOR.PATCH --no-bump --no-changelog \
     --pre-lane release --push
   ```

4. Publish the GitHub release for the new tag. The `Publish Gem Package` workflow checks out that
   exact tag, repeats the tag and version validation, builds the gem, and publishes it to GitHub
   Packages.

5. Confirm the package workflow succeeded and that its registry log reports the exact released gem
   version.

6. Confirm the `Bump Rune` workflow in
   [`CorvidLabs/homebrew-tap`](https://github.com/CorvidLabs/homebrew-tap) opens a checksum-pinned
   formula pull request. The tap pull request must pass all of the following before merge:

   ```sh
   fledge lanes run verify
   brew audit --strict --online corvidlabs/tap/rune
   brew install --build-from-source corvidlabs/tap/rune
   brew test corvidlabs/tap/rune
   ```

   The tap checks both macOS and Linux. If the scheduled workflow has not run yet, dispatch
   `Bump Rune` manually instead of editing an unverified checksum.

8. After the tap pull request merges, install or upgrade from the public tap and verify the
   executable reports the released version:

   ```sh
   brew upgrade corvidlabs/tap/rune || brew install corvidlabs/tap/rune
   rune version --json
   ```
