# Changelog

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
