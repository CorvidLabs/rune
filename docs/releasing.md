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

1. Update local `main`, wait for its CI run to pass, and run the release gate again:

   ```sh
   git switch main
   git pull --ff-only
   fledge lanes run release
   fledge trust verify
   ```

2. Record provenance for the merge commit and verify every commit since the prior release:

   ```sh
   fledge plugins run attest sign --commit HEAD --reviewer human:leif \
     --confidence 1.0 --verdict proceed --tests-passed --human-approved \
     --note "Release commit verified on main"
   git push origin refs/notes/attest
   fledge plugins run attest verify --range PREVIOUS_TAG..HEAD --policy .attest.json
   ```

3. Create and push the tag without changing the already-reviewed version or changelog:

   ```sh
   fledge release MAJOR.MINOR.PATCH --no-bump --no-changelog \
     --pre-lane release --push
   ```

4. Publish the GitHub release for the new tag. The `Publish Gem Package` workflow checks out that
   exact tag, repeats version and provenance validation, builds the gem, and publishes it to
   GitHub Packages.

5. Confirm the package workflow succeeded and that `rune version --json` from the installed gem
   reports the released version.
