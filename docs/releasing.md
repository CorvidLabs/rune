# Releasing rune

Releases are prepared in a pull request and published only from a verified tag on `main`. The
package workflow refuses to publish when the tag differs from the gem/plugin version or when any
commit since the previous tag lacks a passing Attest record.

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
   fledge trust verify
   ```

5. Commit, attest, push, and open a pull request. Do not create the release tag from the prep
   branch.

## Tag and publish after merge

Once the release-prep pull request is merged:

1. Update local `main` and run the release lane against the merge commit:

   ```sh
   git switch main
   git pull --ff-only
   fledge lanes run release
   ```

2. Record and push provenance for the merge commit, then verify every commit since the prior
   release and run the trust gate:

   ```sh
   fledge attest sign --commit HEAD --reviewer human:leif \
     --confidence 1.0 --verdict proceed --tests-passed --human-approved \
     --note "Release commit verified on main"
   git push origin refs/notes/attest
   fledge attest verify --range PREVIOUS_TAG..HEAD --policy .attest.json
   fledge trust verify
   ```

3. Wait for the `main` CI run to pass. If its trust job ran before the Attest note was available,
   rerun that job after pushing the note.

4. Create and push the tag without changing the already-reviewed version or changelog:

   ```sh
   fledge release MAJOR.MINOR.PATCH --no-bump --no-changelog \
     --pre-lane release --push
   ```

5. Publish the GitHub release for the new tag. The `Publish Gem Package` workflow checks out that
   exact tag, repeats version and provenance validation, builds the gem, and publishes it to
   GitHub Packages.

6. Confirm the package workflow succeeded and that its registry log reports the exact released gem
   version.

7. Confirm the `Bump Rune` workflow in
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
