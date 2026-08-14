## MODIFIED

### SPEC SECTION Change Log
- v1: Active spec — CLI framework with dual-mode output and NDJSON envelopes
- v1: Restricted global output-flag extraction to arguments before the first `--`, preserving
  identically named flags for wrapped commands.
| 2026-07-28 | CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery: Adopt and enforce SpecSync 5 for release delivery |
| 2026-07-29 | CHG-0002-address-pr-review-findings-in-release-synchronization-sdd-package-coverage-and: Address PR review findings in release synchronization, SDD package coverage, and publish ref validation |
| 2026-07-29 | CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o: Keep rune watch stdout parseable in agent mode and stop the trust gate passing on an empty commit range |
| 2026-07-29 | CHG-0009-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand, with declarable usage and flags on Command |
| 2026-07-29 | CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and: Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state |
| 2026-07-29 | CHG-0012-restore-full-cli-contract-detail-after-the-help-delta-and-establish-exact-semant: Restore full CLI contract detail after the help delta and establish exact semantic successor coverage |
| 2026-07-29 | CHG-0014-clarify-mixed-help-aliases-and-invocation-local-cli-modes-in-the-exact-cli-contr: Clarify mixed help aliases and invocation-local CLI modes in the exact CLI contract |
| 2026-07-29 | CHG-0015-record-exact-supersession-for-the-committed-cli-help-contract-and-document-cli-r: Finalize the committed CLI help contract and document CLI reuse recovery |
| 2026-07-29 | CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and: Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible |
| 2026-08-14 | CHG-0025-prep-0-3-0-release-bump-version-roll-up-changelog: Bump `Rune::VERSION` to 0.3.0 for the 0.3.0 release prep. No public API or contract change — version constant value only. |
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Register the new `rune session` subcommand by requiring the session module and `SessionCommand` from `lib/rune.rb`. No change to the CLI framework's own public API, output modes, or help contract — the session surface is specified in its own `session` canonical spec. |
