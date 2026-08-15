---
id: CHG-0029-fix-seven-session-defects-found-by-an-independent-grok-kimi-agy-review-wait-for
state: archived
type: bug_fix
base_commit: df43a01ba17acbf6391a5177f08502485551eb1b
---

# Fix seven session defects found by an independent grok/kimi/agy review: wait-for-regex matching the pty echo, a cancelled send locking the session, an unbounded client wait, start reporting success for a dead supervisor, teardown leaving agent workers alive, world-readable parent directories, and assorted robustness gaps

## Intent

Fix seven session defects found by an independent grok/kimi/agy review: wait-for-regex matching the pty echo, a cancelled send locking the session, an unbounded client wait, start reporting success for a dead supervisor, teardown leaving agent workers alive, world-readable parent directories, and assorted robustness gaps

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- Every fix is pinned by a regression test that fails against the old behaviour. Specifically: --wait-for-regex on a marker contained in the sent text waits for the child's real output instead of returning the pty echo (verified: 0s before, ~2.3s after); a send whose caller is killed releases the session immediately instead of holding it for the full --timeout-ms; a send bounds its own wait client-side so a wedged supervisor cannot hang the caller forever; start reports ready only when the supervisor process is actually alive, and fails immediately when it dies rather than waiting out START_TIMEOUT; stop kills the child's process group so an agent CLI's workers do not survive; every directory created under RUNE_HOME is 0700, not just the leaf; a control client cannot take the session down via a partial request line, an unexpected error, EACCES, or a full disk. Full suite green (300 examples), lint clean, no orphaned supervisors.

## No-spec Rationale

Not applicable
