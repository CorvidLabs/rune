---
id: CHG-0072-snap-a-since-that-lands-inside-a-character-forward-instead-of-inventing-u-fff
state: archived
type: bug_fix
base_commit: d57252eaa9995b272e5c72f99ec25857e34a983d
---

# Snap a --since that lands inside a character forward, instead of inventing U+FFFD

## Intent

Snap a --since that lands inside a character forward, instead of inventing U+FFFD

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A --since that lands inside a multi-byte character returns the remainder from the next character start with status ok and zero U+FFFD invented. Measured on こY (E3 81 93 59): since=0 returns こY, since=1 and since=2 and since=3 return Y, since=4 returns empty. The same snap holds for a 4-byte emoji. Cursors already on a character start, and the hole-mapping arithmetic, are unchanged. Four regression tests, each red against the unfixed .scrub path.

## No-spec Rationale

Not applicable
