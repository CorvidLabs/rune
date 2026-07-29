# Changelog

## [Unreleased]

### Fixed

- Route `rune watch`'s live passthrough to stderr in agent mode (`--json`, `--ndjson`, or piped
  stdout) so stdout carries only the result envelope. It previously emitted the wrapped command's
  raw output followed by the JSON, which meant `rune watch --json` produced stdout that did not
  parse.
- Compute an explicit, non-empty commit range for the risk and provenance gates, and fail when that
  range is empty. On a push to `main` the range resolved to zero commits, so both gates reported
  success while inspecting nothing.
- Derive push-event trust ranges from GitHub's exact before/after SHAs so a multi-commit push cannot
  leave earlier commits outside Augur and Attest while only checking the tip.
- Forward the provenance recorded on a squash-merged pull request head onto the landed commit, so a
  push to `main` is verified against the review that actually happened.
- Keep the non-PTY end-to-end examples loadable on platforms where Ruby's optional `pty` extension
  is unavailable, while skipping only the examples that genuinely require a PTY.

### Changed

- Assert end-to-end that the complete stdout of every command parses as a single JSON document, in
  every agent output mode.
- Exercise trust-range selection against real temporary Git histories, including a three-commit
  push, and simulate a Ruby installation without the `pty` extension.

## [v0.2.1] - 2026-07-28

### Fixed

- Preserve `--json` and `--ndjson` flags after the command separator instead of consuming flags
  intended for the wrapped process.
- Decode UTF-8 incrementally so multi-byte characters split across PTY reads remain intact.
- Mirror terminal dimensions into watched child processes and track resize changes while polling.
- Kill and reap watched children when an output sink closes with `EPIPE`.
- Create default watch logs as collision-safe, symlink-resistant, owner-only `0600` files.

### Changed

- Test every supported Ruby minor from 3.0 through 4.0 and enforce strict spec-sync, risk, and
  provenance gates.
- Include linked documentation and examples in the built gem and correct installation guidance.
- Add release version parity, package, smoke, and provenance checks before publishing.

## [v0.2.0] - 2026-07-27

### Other

- Bump version to 0.2.0 (3ef80d1)
- Fix 9 real issues from PR #3's automated review triage, update docs for 0.2.0 (d00a99e)
- 0.2.0 launch prep: PTY timeout flag, TableParser format option, docs, roadmap (#3) (2e68ad9)
