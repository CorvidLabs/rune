---
id: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
state: accepted
type: bug_fix
base_commit: 2ec05cf24663908b061974b8dd8a9caa3fc6ef15
---

# Keep rune watch stdout parseable in agent mode and stop the trust gate passing on an empty commit range

## Intent

Keep rune watch stdout parseable in agent mode and stop the trust gate passing on an empty commit range

## Affected Canonical Specs

- `watch`
- `cli`

## Acceptance Criteria

- 1. `rune watch --json -- CMD` and `rune watch -- CMD | cat` emit stdout that parses whole as a single JSON document; the wrapped child's live output no longer lands on stdout in agent mode. 2. A human running `rune watch` on a real terminal still sees the live passthrough exactly as before, on stdout. 3. An end-to-end spec drives the real bin/rune through a PTY and asserts stdout parses as JSON for every command in every agent output mode, so a regression of this class fails the suite. 4. The CI trust job computes an explicit non-empty commit range per event type and fails loudly when that range contains zero commits, instead of reporting 'PASS (0 commits checked)'. 5. Provenance recorded on a squash-merged pull request head is forwarded to the landed commit so a push to main is genuinely verified. 6. `fledge run trust` falls back to HEAD~1..HEAD locally when origin/main..HEAD is empty.

## No-spec Rationale

Not applicable
